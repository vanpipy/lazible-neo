local function bar()
  print("foo")
end
print("foo")

do
  print("foo")
end

while false do
  print("foo")
end

repeat
  print("foo")
until true

if true then
  print("foo")
else
  print("foo")
end

for i = 1, 2 do
  print("foo")
end
local baz = function()
  print("foo")
end
