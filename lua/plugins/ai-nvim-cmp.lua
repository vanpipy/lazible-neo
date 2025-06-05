return {
  "hrsh7th/nvim-cmp",
  dependencies = { "Kurama622/llm.nvim" },
  optional = true,
  opts = function(_, opts)
    -- if you wish to use autocomplete
    table.insert(opts.sources, 1, {
      name = "llm",
      group_index = 1,
      priority = 100,
    })

    local kind_icons = {
      Text = "",
      Method = "󰆧",
      Function = "󰊕",
      Constructor = "",
      Field = "󰇽",
      Variable = "󰂡",
      Class = "󰠱",
      Interface = "",
      Module = "",
      Property = "󰜢",
      Unit = "",
      Value = "󰎠",
      Enum = "",
      Keyword = "󰌋",
      Snippet = "",
      Color = "󰏘",
      File = "󰈙",
      Reference = "",
      Folder = "󰉋",
      EnumMember = "",
      Constant = "󰏿",
      Struct = "",
      Event = "",
      Operator = "󰆕",
      TypeParameter = "󰅲",
      llm = " ",
    }
    opts.formatting = {
      format = function(entry, vim_item)
        vim_item.kind = string.format("%s %s", kind_icons[vim_item.kind], vim_item.kind)

        vim_item.menu = ({
          buffer = "[Buffer]",
          nvim_lsp = "[LSP]",
          luasnip = "[LuaSnip]",
          nvim_lua = "[Lua]",
          latex_symbols = "[LaTeX]",
          llm = "[LLM]",
        })[entry.source.name]
        return vim_item
      end,
    }
    opts.performance = {
      fetching_timeout = 10000,
    }
  end,
}
