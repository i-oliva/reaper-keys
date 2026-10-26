local limit = require('definitions.config').general.max_repetitions or 10000
return function(value)
    value = value or 1
    assert(type(value) == 'number' and value >= 1 and value <= limit and value % 1 == 0,
        'Repetition count must be an integer from 1 to ' .. limit)
    return value
end
