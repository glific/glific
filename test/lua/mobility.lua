--function mobility ()
--    local state = {x = 0, y = 0}
--
--    local move = function (x, y)
--        state.x = state.x + x
--        state.y = state.y + y
--    end
--
--    local get_position = function ()
--        return {x = state.x, y = state.y}
--    end
--
--    return {
--        move = move,
--        get_position = get_position
--    }
--end

m = inherit_mobility("meow dog")
r = move(7)
f = feels("happy")

return f
