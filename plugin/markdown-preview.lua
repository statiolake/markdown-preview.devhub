-- The commands markdown-preview.nvim has, by the same names.
if vim.g.loaded_markdown_preview_devhub then
  return
end
vim.g.loaded_markdown_preview_devhub = true

vim.api.nvim_create_user_command('MarkdownPreview', function()
  require('markdown-preview').open(0)
end, { desc = 'Open the Markdown preview beside this window' })
vim.api.nvim_create_user_command('MarkdownPreviewStop', function()
  require('markdown-preview').stop(0)
end, { desc = 'Close the Markdown preview' })
vim.api.nvim_create_user_command('MarkdownPreviewToggle', function()
  require('markdown-preview').toggle(0)
end, { desc = 'Open or close the Markdown preview' })
