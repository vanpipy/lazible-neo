local bar = "bar"
local foo = "foo"
print(foo)
print(foo)
print(foo)
print(foo)
print(bar)
print(bar)
-- __PRINT_VAR_START
print([==[┆┆ ╎bar╎ ┊1┊:]==], vim.inspect(bar))
print([==[┆┆ ╎foo╎ ┊1┊:]==], vim.inspect(foo))-- __PRINT_VAR_END
