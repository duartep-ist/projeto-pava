module Exceptional

struct Condition
    is_error::Bool
    exception::Exception
end

exception_handler_dicts::Vector = []
chosen_restart = nothing
restart_handler_dicts::Vector = []

function handling(func, handlers...) #TODO: Not use try-catch
    handler_dict = Dict(handlers)
    push!(exception_handler_dicts, handler_dict)
    func()
    pop!(exception_handler_dicts)
end

reciprocal(x) = x == 0 ? Base.error(DivisionByZero()) : 1/x


struct DivisionByZero <: Exception end

handling(DivisionByZero => (c)->println("I saw a division by zero")) do
    reciprocal(0)
end

handling(DivisionByZero => (c)->println("I saw it too")) do
    handling(DivisionByZero => (c)->println("I saw a division by zero")) do
        reciprocal(0)
    end
end

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
    restart_handler = Dict(restarts)
    push!(restart_handler_dicts, restart_handler)
    func()
    for handler_dict in Iterators.reverse(exception_handler_dicts)
        if typeof(e) in keys(handler_dict)
            handler_dict[typeof(e)](e)
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


function signal(exception::Exception)
    treated = false
    for handler_dict in Iterators.reverse(exception_handler_dicts)
        if typeof(exception) in keys(handler_dict)
            handler_dict[typeof(exception)](exception)
    
            break #TODO: check if needed    
        end
    end
    return treated
end

function Base.error(exception::Exception)
    if !signal(exception)
        throw(exception)
    end
end


struct LineEndLimit <: Exception end

print_line(str, line_end=20) =
let col = 0 
    for c in str print(c)
        col += 1
        if col == line_end
            Base.error(LineEndLimit())
            col = 0
        end
    end
end

handling(LineEndLimit => (c)->println()) do
    print_line("Hi, everybody! How are you feeling today?") 
end


end