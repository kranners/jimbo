local M = {}

local home = os.getenv("HOME")

M.latte_root = vim.fn.resolve(home .. "/Documents/Latte")
M.frappuccino_root = vim.fn.resolve(M.latte_root .. "/frappuccino/docs")
M.stack_root = vim.fn.resolve(M.latte_root .. "/Stack")

M.daily_template_path = vim.fn.resolve(M.latte_root .. "/Templates/Daily.md")

return M
