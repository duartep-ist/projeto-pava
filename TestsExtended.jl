try
	ExceptionalExtended
catch e
	if typeof(e) == UndefVarError
		 println(stderr, "ERROR: ExceptionalExtended library not found. Did you mean to run RunTestsExtended.jl instead?")
		 exit(1)
	else
		 rethrow()
	end
end

using Test
