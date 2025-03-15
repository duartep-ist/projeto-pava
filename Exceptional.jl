module Exceptional

struct Condition
    is_error::Bool
    exception::Exception
end

exception_handler_dicts::Vector = []
chosen_restart = nothing
restart_handler_dicts::Vector = []

function handling(func, handlers...)
    handler_dict = Dict(handlers)
    push!(exception_handler_dicts, handler_dict)

    try
        func() # or func(args...)
    catch e
        if typeof(e) in keys(handler_dict)
            handler_dict[typeof(e)](e)
        else #exception is not treated in handlers
            rethrow()
        end #TODO: Case of signals
    finally
        pop!(exception_handler_dicts)
    end
end

reciprocal(x) = x == 0 ? throw(DivisionByZero()) : 1/x

struct DivisionByZero <: Exception end

struct EscapedException <: Exception end

function to_escape(func)
    # TODO usar let ?
    did_escape = false
    escaped = EscapedException()
    ret_val = nothing
    try
        func((ret) -> (did_escape = true; ret_val = ret; throw(escaped)))
    catch
        if did_escape
            return ret_val
        else
           rethrow()
        end
    end
end


function with_restart(func, restarts...)
    try
        func()
    catch e
        if typeof(e) != Condition
            rethrow()
        else
            for handler_dict in Iterators.reverse(exception_handler_dicts)
                if typeof(e) in keys(handler_dict)
                    handler_dict[typeof(e)](e)()
                    if !isnothing(chosen_restart)
                        # TODO
                        break
                    end
                end
            end
            if isnothing(chosen_restart)
                if (e.is_error)
                    throw(e.exception)
                end
            end
        end
    end
end


signal(exception::Exception) = throw(Condition(false, exception))
Base.error(exception::Exception) = throw(Condition(true, exception))

mystery(n) =
    1 +
    to_escape() do outer
        1 +
        to_escape() do inner
            1 +
            if n == 0
                inner(1)
            elseif n == 1
                outer(1)
            else
                1
        end
    end
end

end