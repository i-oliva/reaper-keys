local BindingListView = require('gui.binding_list.View')
local buildCommandWithCompletions = require 'build'
local gui_utils = require('gui.utils')
local reaper_state = require('reaper_state')
local search = require 'binding_search'
local GUI = require('gui.core')
local dispatch = require 'dispatch'
local definition_tables = require "definitions.bindings"
local utils = require 'utils'

local binding_list = {}

-- this reverses the keys and values of entries
local function getBindings(entries)
  local bindings = {}
  if not entries then return bindings end

  for entry_key,entry_value in pairs(entries) do
    if utils.isFolder(entry_value) then
      local folder_table = entry_value[2]
      local folder_bindings = getBindings(folder_table)

      for action_name_from_folder,binding_from_folder in pairs(folder_bindings) do
        bindings[action_name_from_folder] = entry_key .. binding_from_folder
      end
    else
      bindings[entry_value] = entry_key
    end
  end

  return bindings
end

local function getAllBindings()
  local bindings = {}

  for context,context_definitions in pairs(definition_tables) do
    bindings[context] = {}
    for action_type,action_type_definitions in pairs(context_definitions) do
      bindings[context][action_type] = getBindings(action_type_definitions)
    end
  end

  return bindings
end

local function createBindingList(state)
  local data = {}
  local _, state_entries = buildCommandWithCompletions(state, false)
  state_entries = state_entries or {}
  local bindings = getAllBindings()

  for context,context_bindings in pairs(bindings) do
    for action_type,action_type_bindings in pairs(context_bindings) do
      local state_bindings = getBindings(state_entries[action_type])

      for action_name,action_binding in pairs(action_type_bindings) do
        local row = {
          match_score = 0,
          matched_indices = {},
          context = context,
          action_name = action_name,
          action_binding = action_binding,
          action_type = action_type,
        }

        if state_bindings[action_name] then
          row.is_valid_in_state = true
          row.action_binding = state_bindings[action_name]
        end

        table.insert(data, row)
      end
    end
  end

  return data
end

local function getElementValues(view)
  local context_i, context = view.elements.context_filter:val()
  local action_type_i, action_type = view.elements.action_type_filter:val()
  return {
    binding_list_box = view.elements.binding_list_box:val(),
    state_filter_active = view.elements.state_filter_active:val(nil, true),
    context_filter_active = view.elements.context_filter_active:val(nil, true),
    context = context,
    context_i = context_i,
    action_type_filter_active = view.elements.action_type_filter_active:val(nil, true),
    action_type = action_type,
    action_type_i = action_type_i,
    query = view.elements.query:val(),
  }
end

function binding_list.open(state)
  local saved_props = reaper_state.get("binding_list")
  if not saved_props then
    saved_props = {
      window = {},
      element_values = {}
    }
  end
  local view = BindingListView:new(saved_props)
  local element_values = {}
  local full_binding_list = createBindingList(state)
  view.elements.binding_list_box.list = full_binding_list

  local function updateLoop()
    local new_element_values = getElementValues(view)
    if search.changed(element_values, new_element_values) then
      local box = view.elements.binding_list_box
      box.list = search.filter(full_binding_list, new_element_values)
      view.selected_i = #box.list > 0 and 1 or 0
      box:val(view.selected_i)
      box.windowY = 1
      box:recalculateWindow()
      box:redraw()
    end
    element_values = new_element_values

    if view.window.state.resized then
      view.window.state.resized = false
      view:redraw()
    end

    if view.action_executed then
      local selected_row = view.elements.binding_list_box.list[view.selected_i]
      view.action_executed = false
      if not selected_row then return end
      local candidate = {context = state.context, mode = state.mode, key_sequence = selected_row.action_binding}
      local command = selected_row.is_valid_in_state and buildCommandWithCompletions(candidate, true)
      if not command then
        reaper.ShowMessageBox('This binding needs a motion, selection, register, or a different context.\n' ..
          'Close this window and type ' .. selected_row.action_binding .. ' in Arrange/MIDI; follow the completion hints.',
          'Composed binding', 0)
        return
      end
      view.window:close()
      -- Never bypass composition or send a MIDI action to the main section.
      local ok, result = xpcall(function() return dispatch(state, command) end, debug.traceback)
      if ok then
        reaper_state.setState(result)
      else
        local recovered = reaper_state.getState()
        recovered.key_sequence, recovered.macro_recording = '', false
        reaper_state.setState(recovered)
        require('log').error(result)
      end
    end
  end

  local function saveState()
    local binding_list_state = {
      window = gui_utils.getWindowSettings(),
      element_values = element_values
    }
    reaper_state.set("binding_list", binding_list_state)
  end

  reaper.atexit(saveState)

  view.window:open()
  view.window.state.focusedElm = view.elements.query

  GUI.func = updateLoop
  GUI.funcTime = 0
  GUI.Main()
end

return binding_list
