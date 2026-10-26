-- Search has no GUI dependency. Rows are scored once per query; moving the
-- selection or toggling filters never repeats fuzzy matching.
local fuzzy = require('fuzzy').fuzzy_match
local M = {}
local filter_keys = {'query', 'state_filter_active', 'context_filter_active',
    'context', 'action_type_filter_active', 'action_type'}

function M.changed(before, after)
    for _, key in ipairs(filter_keys) do
        if before[key] ~= after[key] then return true end
    end
    return false
end

function M.filter(rows, filters)
    local result, query = {}, filters.query or ''
    for _, row in ipairs(rows) do
        if row._query ~= query then
            row._query = query
            row.sequential_match, row.match_score, row.matched_indices = true, 0, {}
            if query ~= '' then
                local matched, score, indices = fuzzy(query, row.action_name)
                local key_match, key_score = fuzzy(query, row.action_binding or '')
                row.sequential_match = matched or key_match
                row.match_score = math.max(matched and score or -math.huge, key_match and key_score or -math.huge)
                row.matched_indices = matched and indices or {}
            end
        end
        if row.sequential_match
            and (not filters.state_filter_active or row.is_valid_in_state)
            and (not filters.context_filter_active or row.context == filters.context or row.context == 'global')
            and (not filters.action_type_filter_active or row.action_type == filters.action_type) then
            result[#result + 1] = row
        end
    end
    table.sort(result, function(a, b)
        if query ~= '' and a.match_score ~= b.match_score then return a.match_score > b.match_score end
        if a.action_type ~= b.action_type then return a.action_type > b.action_type end
        if a.action_name ~= b.action_name then return a.action_name < b.action_name end
        if a.action_binding ~= b.action_binding then return a.action_binding < b.action_binding end
        return a.context < b.context
    end)
    return result
end
return M
