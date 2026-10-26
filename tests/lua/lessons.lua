local t = dofile('tests/lua/support.lua')
local count = 0
for _, lesson in ipairs(require 'coach.lessons') do
    for _, check in ipairs(lesson.checks) do
        local command = t.build(check[1], check[4] or 'main', check[3] or 'normal')
        assert(command, lesson.title .. ': no command for ' .. check[1])
        local action = command.action_keys[1]
        if type(action) == 'table' then action = action[1] end
        t.eq(action, check[2], lesson.title .. ': ' .. check[1])
        count = count + 1
    end
end
print(('PASS %d coach key sequences verified against real definitions'):format(count))
