---@param b string
---@param c string
---@param d table
---@param e table
---@param f table
---@param g function
---@param h string
---@param k string
---@param l string
---@param i string
local function bar(a, b, c, d, e, f, g, h, k, l, i, j)
  a = a + 1
  print(b)
  print(c + 1)
  print(d[1])
  print(e.e)
  print(f:f())
  print(g())
  if h then end
  while k do end
  repeat until l
  i = 'i'
  print(j)

  return a, i
end

---@param a integer
local function foo(a)
  for j = 1, 5 do
    local b = 'b'
    local c = 'c'
    local d = {'d'}
    local e = { e = 'e' }
    local f = {}
    function f.f(self) return 'f' end
    local g, h = function() return 'g' end, 'h'
    local i
    local k = 'k'
    local l = 'l'

    local a, i = bar(a, b, c, d, e, f, g, h, k, l, i, j)

    print(a)
    print(i)
  end
end
