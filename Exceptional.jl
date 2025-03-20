module Exceptional

exception_handler_dicts::Vector = []
restart_handler_dicts::Vector = []

function handling(func, handlers...)
    handler_dict = Dict(handlers)
    push!(exception_handler_dicts, handler_dict)
    func()
    # TODO perguntar ao stor se podemos usar try finally aqui
    pop!(exception_handler_dicts)
end

struct EscapedException <: Exception end

function to_escape(func)
    # TODO usar let ?
    did_escape = false
    escaped = EscapedException()
    ret_val = nothing
    try
        func((ret) -> (did_escape = true; ret_val = ret; throw(escaped)))
    catch # TODO checkar se temos de ter id único para o escaped
        if did_escape
            return ret_val
        else
           rethrow()
        end
    end
end

# TODO perguntar ao stor se podemos usar try catch aqui
function with_restart(func, restarts...)
    restart_handler = Dict(restarts)
    push!(restart_handler_dicts, restart_handler)
    func()
    pop!(restart_handler_dicts)
end

function available_restart(name)
    for restart_dict in Iterators.reverse(restart_handler_dicts)
            if name in keys(restart_dict)
                return true
            end
        end
    return false
end

function invoke_restart(name, args...)
    for restart_dict in Iterators.reverse(restart_handler_dicts)
        if name in keys(restart_dict)
            restart_dict[name](args)
            return 
        end
    end
end

function signal(exception::Exception)
    for handler_dict in Iterators.reverse(exception_handler_dicts)
        if typeof(exception) in keys(handler_dict)
            handler_dict[typeof(exception)](exception)
            # if invoke restart foi chamado
                # return true
        end
    end
    return false
end

function Base.error(exception::Exception)
    if !signal(exception)
        throw(exception)
    end
end

struct DivisionByZero <: Exception end

reciprocal(x) = x == 0 ? Base.error(DivisionByZero()) : 1/x

handling(DivisionByZero => (c)->println("I saw a division by zero")) do
    reciprocal(0)
end

handling(DivisionByZero => (c)->println("I saw it too")) do
    handling(DivisionByZero => (c)->println("I saw a division by zero")) do
        reciprocal(0)
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