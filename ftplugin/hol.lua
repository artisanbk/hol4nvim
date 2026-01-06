-- Prevent reloading
if vim.b.did_fyplugin then 
  return
end

vim.b.did_ftplugin = 1

vim.op
