try
    @macroexpand @handler_case(nothing)
catch e
    if typeof(e) == UndefVarError
        println(stderr, "Execute \"RunTestsExtended.jl\" instead.")
        exit(1)
    else
        rethrow()
    end
end

using Test

# This represents a type of error which could be thrown by code belonging to the user of the library.
# It isn't a subtype of Exception since that's not guaranteed for user errors.
struct UserError
end


square_root(value) =
    !isa(value, Real) ?
        error(TypeError(:square_root, "", Real, value)) :
        value < 0 ?
            error(DomainError(value)) :
            sqrt(value)


# The @handler_case macro

# For convenience, we implement a @handler_case macro inspired by Common Lisp's handler-case. The
# first argument to @handler_case is the expression to be evaluated. The rest of the arguments are
# tuples containing the exception type, the parameter name, and the expression to be evaluated when
# that exception occurs.

# @handler_case returns the value of the first expression if there were no exceptional situations.
@test @handler_case(
    square_root(4),
    (DomainError, (), "Domain error!"),
    (TypeError, (), "Type error!")
) == 2

# And, if an exceptional situation occurred, it returns the result of the corresponding expression.
@test @handler_case(
    square_root(-1),
    (DomainError, (), "Domain error!"),
    (TypeError, (), "Type error!")
) == "Domain error!"
@test @handler_case(
    square_root(""),
    (DomainError, (), "Domain error!"),
    (TypeError, (), "Type error!")
) == "Type error!"

# You can add a parameter to use the exception object within the expression.
@test @handler_case(
    square_root(-1),
    (DomainError, (e), "Error: tried to compute the square root of $(e.val).")
) == "Error: tried to compute the square root of -1."

# You can also add a case for when no exceptional situation occurs, which takes the result of the
# first expression as an argument. The no error case is identified by a literal "nothing" in the
# first element of the tuple.
@test @handler_case(
    square_root(4),
    (DomainError, (e), "Error: tried to compute the square root of $(e.val)."),
    (nothing, (result), "The result is $(result)!")
) == "The result is 2.0!"

# Only one of such cases is allowed.
@test_throws ErrorException @macroexpand @handler_case(
    square_root(4),
    (nothing, (result), 1),
    (nothing, (result), 2)
)

# As in Common Lisp, @handler_case will stop the execution of the expression as soon as an
# exception with its type contained in the list is signaled. This means that you can't invoke
# restarts from inside @handler_case.
@test_throws UnavailableRestartException @handler_case(
    square_root(-1),
    (DomainError, (), invoke_restart(:return_zero))
)

# You can, however, return from functions and break/continue from loops from inside @handler_case.
function square_root_vector_return(input)
    output = Vector()
    for value in input
        @handler_case(
            push!(output, square_root(value)),
            (DomainError, (), return "Error!")
        )
    end
    output
end
@test square_root_vector_return([0, -1, 4]) == "Error!"


function square_root_vector_break(input)
    output = Vector()
    for value in input
        @handler_case(
            push!(output, square_root(value)),
            (DomainError, (), break)
        )
    end
    output
end
@test square_root_vector_break([0, -1, 4]) == [0]

function square_root_vector_replace(input)
    output = Vector()
    for value in input
        push!(output, @handler_case(
            square_root(value),
            (DomainError, (), "Error!")
        ))
    end
    output
end
@test square_root_vector_replace([0, -1, 4]) == [0, "Error!", 2]


# @handler_case evaluates each of its arguments only once.
@test let expr_eval_count = 0, type_eval_count = 0
    @handler_case(
        (expr_eval_count += 1; square_root(0)),
        ((type_eval_count += 1; DomainError), (), nothing)
    )
    expr_eval_count == 1 && type_eval_count == 1
end

# Julia thrown exceptions that happen during the evaluation of the exception types are propagated.
@test_throws UserError @handler_case(
    123,
    (throw(UserError()), (), nothing)
)


# The @restart_case macro

# With @restart_case, we can implement the above functions into a single one using restarts. Like
# @handler_case, @restart_case supports return, break and continue.
function square_root_vector_restartable(input)
    output = Vector()
    for value in input
        push!(output, @restart_case(
            square_root(value),
            (replace_with, (v), v),
            (omit, (), continue),
            (stop, (), break),
            (give_up, (), return "Error!")
        ))
    end
    output
end

@test square_root_vector_restartable([0, 1, 4]) == [0, 1, 2]
@test handling(DomainError => (c)->invoke_restart(:replace_with, "Oh no!")) do
    square_root_vector_restartable([0, -1, 4])
end == [0, "Oh no!", 2]
@test handling(DomainError => (c)->invoke_restart(:omit)) do
    square_root_vector_restartable([0, -1, 4])
end == [0, 2]
@test handling(DomainError => (c)->invoke_restart(:stop)) do
    square_root_vector_restartable([0, -1, 4])
end == [0]
@test handling(DomainError => (c)->invoke_restart(:give_up)) do
    square_root_vector_restartable([0, -1, 4])
end == "Error!"


# Like with_restart, @restart_case supports several parameters in each case, as well as restart options, such as test, report, and interactive.
abstract type ArithmeticError <: Exception end
struct DivisionByZero <: ArithmeticError end
divide(dividend, divisor) =
    @restart_case(
        divisor == 0 ?
            error(DivisionByZero()) :
            dividend/divisor,

        (return_zero, (),
            report = () -> "Returns 0",
            test = () -> dividend == 0,
            0),
        (return_value, (x),
            report = () -> "Returns the specified value",
            x),
        (retry_using, (a, b),
            report = () -> "Recomputes the calculation using the specified arguments",
            divide(a, b))
    )

@test handling(DivisionByZero => (c)->invoke_restart(:retry_using, 1, 2)) do
    divide(2, 0)
end == 1/2
@test handling(DivisionByZero => (c)->invoke_restart(:return_zero)) do
    divide(0, 0)
end == 0
# Here, it won't work because of the test function.
@test_throws UnavailableRestartException handling(DivisionByZero => (c)->invoke_restart(:return_zero)) do
    divide(1, 0)
end == 0

# However, you can't pass a number of arguments different than expected.
@test_throws MethodError handling(DivisionByZero => (c)->invoke_restart(:retry_using, 1)) do
    divide(2, 0)
end
@test_throws MethodError handling(DivisionByZero => (c)->invoke_restart(:retry_using, 1, 2, 3)) do
    divide(2, 0)
end

# You can put options in any order you want.
@test handling(DivisionByZero => (c)->invoke_restart(:a)) do
    @restart_case(
        signal(DivisionByZero()),
        (report = ()->"Return 123", a, (), 123)
    )
end == 123
@test handling(DivisionByZero => (c)->invoke_restart(:a)) do
    @restart_case(
        signal(DivisionByZero()),
        (a, report = ()->"Return 123", (), 123)
    )
end == 123
@test handling(DivisionByZero => (c)->invoke_restart(:a)) do
    @restart_case(
        signal(DivisionByZero()),
        (a, (), report = ()->"Return 123", 123)
    )
end == 123
@test handling(DivisionByZero => (c)->invoke_restart(:a)) do
    @restart_case(
        signal(DivisionByZero()),
        (a, (), 123, report = ()->"Return 123")
    )
end == 123

# Julia thrown exceptions that happen during the evaluation of the options are propagated.
@test_throws UserError @restart_case(
    123,
    (a, (), nothing, report = throw(UserError()))
)


# transform_errors()

square_root_2(x) = transform_errors() do
    sqrt(x)
end

@test @handler_case(
    square_root_2(4),
    (DomainError, (), "Domain error!"),
) == 2
@test @handler_case(
    square_root_2(-1),
    (DomainError, (), "Domain error!"),
) == "Domain error!"



# handling(DivisionByZero => (c)->invoke_restart(:return_value, "Error!")) do
#     divide(2, 0)
# end
# @test handling(DivisionByZero => (c)->invoke_restart(:return_value, -1)) do
#     divide(2, 0)
# end == -1
