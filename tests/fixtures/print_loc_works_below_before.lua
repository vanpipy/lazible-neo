local a, b =
  function()
    print "a"
  end, function()
    print "b"
    if true then
      for _, value in ipairs(some_table) do
        print "a"
      end
    elseif false then
      print "elseif"
    else
      print "else"
    end
  end
