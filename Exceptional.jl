module Exceptional

struct RestartInfo
    restarts::Dict{Symbol, Function}
    escape::Function
end

struct ExceptionHandler
    exception::DataType
    handler::Function
end

struct RestartResult
    func::Function
    args::Tuple
end


handling_stack::Vector{Vector{ExceptionHandler}} = []
restart_stack::Vector{RestartInfo} = []

function handling(func, handlers...)
    let handler_list = [ExceptionHandler(h.first, h.second) for h in handlers]
        push!(handling_stack, handler_list)
        try
            func()
        finally
            pop!(handling_stack)
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
    let restart_handler_dict = Dict(Iterators.reverse(restarts)), result = nothing
        try
            result = to_escape() do escape
                push!(restart_stack, RestartInfo(restart_handler_dict, escape))
                func()
            end
        finally
            pop!(restart_stack)
            if result isa RestartResult
                return result.func(result.args...)
            end
        end
    end
end

function available_restart(name)
    for info in Iterators.reverse(restart_stack)
        if name in keys(info.restarts)
            return true
        end
    end
    false
end

function invoke_restart(name, args...)
    for info in Iterators.reverse(restart_stack)
        if name in keys(info.restarts)
            info.escape(RestartResult(info.restarts[name], args))
            return
        end
    end
    throw(UnavailableRestartException(name))
end

function signal(exception::Exception)
    for handler_frame in Iterators.reverse(handling_stack)
        for handler in handler_frame
            if exception isa handler.exception
                handler.handler(exception)
                break
            end
        end
    end
end

function Base.error(exception::Exception)
    signal(exception)
    throw(exception)
end


# Library errors

struct UnavailableRestartException <: Exception
    name::Symbol
end
function Base.showerror(io::IO, e::UnavailableRestartException)
    print(io, "UnavailableRestartException: the restart named \"$(e.name)\" is not available.")
end


export to_escape, handling, with_restart, available_restart, invoke_restart, signal, UnavailableRestartException

end
