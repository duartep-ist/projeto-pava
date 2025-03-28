module ExceptionalExtended

struct Restart
    name::Symbol
    func::Function
    test::Function
    report::Function
    interactive::Function
end

struct RestartInfo
    handler_dict::Dict{Symbol, Restart}
    escape::Function
    caller::Function
end

exception_handler_dicts::Vector{Vector{Function}} = []
restart_stack::Vector{RestartInfo} = []

function handling(func, handlers...)
    let
        handler_dict = Vector(handlers)
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
    let did_escape = false, ret_val = nothing
        escape(ret::Any) = begin did_escape = true; ret_val = ret; throw(escaped) end
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


function parse_restart(restart)
    let
        name = restart.first
        func = nothing
        test = () -> true
        report = () -> (restart.first)
        interactive = () -> ()

        if isa(restart.second, Tuple) # (:name, (:report, report, :interactive, interactive, :test, test))
            func = restart.second[1]
            for i in 2:length(restart.second)
                if restart.second[i] == :test
                    test = restart.second[i+1]
                elseif restart.second[i] == :report
                    report = restart.second[i+1]
                elseif restart.second[i] == :interactive
                    interactive = restart.second[i+1]
                end
                i = i+1
            end
        else # (:name, func)
            func = restart.second
        end
        return Restart(name, func, test, report, interactive)
    end
end

function print_restarts(exception)
    let restarts::Vector{Pair{Function, Restart}} = [], n = 1, chosen::Union{Nothing, Pair{Function, Restart}} = nothing
    println("Error of type: $exception")
    println("Available restarts:")
    for info in Iterators.reverse(restart_stack)
        for r in values(info.handler_dict)
            if r.test()
                push!(restarts, Pair(info.escape, r))
                println("$n: $(r.name) $(r.report())")
                n = n + 1
            end
        end
    end

    #TODO adicionar default restarts
    
    print("Choose one restart: ")
    chosen = restarts[parse(Int, readline())]

    chosen.first(chosen.second.func(chosen.second.interactive()...))
    end
end

function with_restart(func, restarts...)
    let
        restart_handler_dict = Dict([(r.first => parse_restart(r)) for r in restarts])
        push!(restart_handler_dict, )
        try
            to_escape() do escape
                push!(restart_stack, RestartInfo(restart_handler_dict, escape, func))
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
            info.escape(info.handler_dict[name].func(args...))
            return
        end
    end
end

function signal(exception::Exception)
    for handler_dict in Iterators.reverse(exception_handler_dicts)
        for t in supertypes(typeof(exception))
            if t in keys(handler_dict)
                handler_dict[typeof(exception)](exception)
                break
            end
        end    
    end
end

#=
with_restart (:restart=>()) do 
    with_restart (:restart2=>()) do
        func()
=#

#=
handling(Exception => ()->(), DivisionByZero => () ->()) do
    handling(Exception => ()->(), DivisionByZero => () ->()) do
    error(DivisionByZero())
end


handling     divison

  handling     any

    handling    divison, exception, any
=#


function Base.error(exception::Exception)
    signal(exception)
    print_restarts(exception)
    throw(exception)
end

macro handler_case(ex, cases...)
	esc(:(handling($(
		[:(
			$(case.args[1]) => $(case.args[2]) -> $(case.args[3])
		) for case in cases]...
	)) do
        $ex
    end))
end

macro restart_case(ex, cases...)
	esc(:(with_restart($(
		[:(
			$(case.args[1]) => $(case.args[2]) -> $(case.args[3])
		) for case in cases]...
	)) do
        $ex
    end))
end

# Example
struct DivisionByZero <: Exception end

divide(a, b) = with_restart(:return_zero => (() -> 0, :test, () -> false),
                            :return_value => (identity, :interactive, ()->(let ret::String
                                                                               print("Enter a return value: ")
                                                                               ret = readline()
                                                                               ret
                                                                           end)),
                            :retry_using => (divide, :report, ()->"Retry using another numerator and denominator",
                                                     :interactive, ()->(let a::Int, b::Int
                                                                            print("Enter a numerator: ")
                                                                            a = parse(Int, readline())
                                                                            print("Enter a denominator: ")
                                                                            b = parse(Int, readline())
                                                                            a,b
                                                                        end))) do
                            b == 0 ? 
                            error(DivisionByZero()) :
                            a/b
end

export to_escape, handling, with_restart, available_restart, invoke_restart, signal, handler_case, restart_case, divide, DivisionByZero
end
