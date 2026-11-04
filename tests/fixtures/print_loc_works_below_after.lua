local a, b =
  function()
    print "a"
  end, function()
    print "b"
    if true then
      for _, value in ipairs(some_table) do
        print "a"
        -- __PRINT_LOC_START
        print([==[┆b#if#for┆ ┊1┊]==])-- __PRINT_LOC_END
      end
    elseif false then
      print "elseif"
    else
      print "else"
    end
  end
