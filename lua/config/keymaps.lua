-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set

map("n", "<leader>w", "<esc><cmd>w<cr>", { desc = "saved" })
map("n", "gl", "$", { desc = "go last end the line" })
map("n", "ga", "^", { desc = "go ahead end the line" })
