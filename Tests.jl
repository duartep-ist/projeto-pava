include("Exceptional.jl")
using .Exceptional
using Test


# Escaping

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

@test mystery(0) == 3
@test mystery(1) == 2
@test mystery(2) == 4


# Handling

@test handling(() -> 123) == 123

struct DivisionByZero <: Exception
end

simple_reciprocal(x) = x == 0 ? Base.error(DivisionByZero()) : 1/x

@test to_escape() do exit
    handling(DivisionByZero => (c) -> exit(true)) do
        simple_reciprocal(0)
    end
end

@test let saw0 = false, saw1 = false
    to_escape() do exit
        handling(DivisionByZero => (c)-> (saw0 = true; exit(true))) do
            handling(DivisionByZero => (c)-> (saw1 = true)) do
                simple_reciprocal(0)
            end
        end
    end
    saw0 && saw1
end


struct LineEndLimit <: Exception
end

function print_line(str, signal_func, line_end=20)
    global line = ""
    let col = 0 
        for c in str
            line *= c
            col += 1
            if col == line_end
                signal_func(LineEndLimit())
                col = 0
            end
        end
    end
    line
end

@test print_line("Hi, everybody! How are you feeling today?", signal) == "Hi, everybody! How are you feeling today?"
@test begin
    to_escape() do exit
        handling(LineEndLimit => (c)->exit()) do
            print_line("Hi, everybody! How are you feeling today?", signal)
        end
    end
    line == "Hi, everybody! How a"
end
@test handling(LineEndLimit => (c) -> global line *= "\n") do
    print_line("Hi, everybody! How are you feeling today?", signal)
end == "Hi, everybody! How a\nre you feeling today\n?"

@test begin
    to_escape() do exit
        handling(LineEndLimit => (c)->exit()) do
            print_line("Hi, everybody! How are you feeling today?", error)
        end
    end
    line == "Hi, everybody! How a"
end
@test_throws LineEndLimit handling(LineEndLimit => (c) -> global line *= "\n") do
    print_line("Hi, everybody! How are you feeling today?", error)
end
@test line == "Hi, everybody! How a\n"


# Restarts

reciprocal(value) =
    with_restart(
        :return_zero => ()->0,
        :return_value => identity,
        :retry_using => reciprocal
    ) do
        value == 0 ?
            error(DivisionByZero()) :
            1/value
    end

@test handling(DivisionByZero => (c)->invoke_restart(:return_zero)) do
    reciprocal(0)
end == 0
@test handling(DivisionByZero => (c)->invoke_restart(:return_value, 123)) do
    reciprocal(0)
end == 123
@test handling(DivisionByZero => (c)->invoke_restart(:retry_using, 10)) do
    reciprocal(0)
end == 0.1

@test handling(DivisionByZero =>
    (c) -> for restart in (:return_one, :return_zero, :die_horribly)
        if available_restart(restart)
            invoke_restart(restart)
        end
    end
) do
    reciprocal(0)
end == 0

@test let count = 0
    handling(DivisionByZero => (c) -> (count = count + 1; invoke_restart(:retry_using, count == 1 ? 0 : 10))) do
        reciprocal(0)
    end == 0.1
end
