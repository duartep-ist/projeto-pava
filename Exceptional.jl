module Exceptional

struct RestartInfo
    handler_dict::Dict{Symbol, Function}
    escape::Function
end

exception_handler_dicts::Vector{Dict{Any, Function}} = []
restart_stack::Vector{RestartInfo} = []

function handling(func, handlers...)
    let handler_dict = Dict(handlers)
        push!(exception_handler_dicts, handler_dict)
        try
            func()
        finally
            pop!(exception_handler_dicts)
        end
    end
end

struct EscapedException <: Exception end
escaped = EscapedException()

function to_escape(func)
    let did_escape = false, ret_val = nothing, escape(ret::Any) = begin did_escape = true; ret_val = ret; throw(escaped) end
        escape() = escape(nothing)
        try
            func(escape)
        catch
            if did_escape
                return ret_val
            else
                rethrow()
            end
        end
    end
end

function with_restart(func, restarts...)
    let restart_handler_dict = Dict(restarts)
        try
            to_escape() do escape
                push!(restart_stack, RestartInfo(restart_handler_dict, escape))
                func()
            end
        finally    
            pop!(restart_stack)
        end
    end
end

function available_restart(name)
    for info in Iterators.reverse(restart_stack)
        if name in keys(info.handler_dict)
            return true
        end
    end
    false
end

function invoke_restart(name, args...)
    for info in Iterators.reverse(restart_stack)
        if name in keys(info.handler_dict)
            info.escape(info.handler_dict[name](args...))
            return
        end
    end
    throw(UndefinedRestartException(name))
end

function signal(exception::Exception)
    for handler_dict in Iterators.reverse(exception_handler_dicts)
        if typeof(exception) in keys(handler_dict)
            handler_dict[typeof(exception)](exception)
        end
    end
end

function Base.error(exception::Exception)
    signal(exception)
    throw(exception)
end


# Library errors

struct UndefinedRestartException <: Exception
    name::Symbol
end
function Base.showerror(io::IO, e::UndefinedRestartException)
    print(io, "UndefinedRestartException: the restart named \"$(e.name)\" is not available.")
end


export to_escape, handling, with_restart, available_restart, invoke_restart, signal, UndefinedRestartException

end
