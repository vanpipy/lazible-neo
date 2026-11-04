local function a(x, y, z)
  print(x)
  y = y + z
  return x, y, z
end

local c, d, e = a(1, 2, 3)
c, d, e = a(c + 1, d + 1, e + 1)
