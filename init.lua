-- ~/.config/nvim/init.lua
-- Конфиг Neovim для писательства:
-- русская орфография, режим фокуса, markdown, ИИ.

-- 1. Лидер-клавиша (задаётся ДО загрузки плагинов)
vim.g.mapleader = " "        -- пробел как основная лидер-клавиша
vim.g.maplocalleader = " "

-- 2. Базовые настройки под прозу
local opt = vim.opt
opt.number = false            -- номера строк для текста не нужны
opt.wrap = true               -- переносить длинные строки
opt.linebreak = true          -- переносить по словам, а не по буквам
opt.breakindent = true        -- сохранять отступ при переносе
opt.showbreak = "↳ "          -- маркер переноса
opt.mouse = "a"               -- мышь, если терминал её поддерживает
opt.clipboard = "unnamedplus" -- общий системный буфер (нужен xclip/wl-clipboard)
opt.termguicolors = true      -- 24-битный цвет (нужен современный терминал)
opt.scrolloff = 8             -- держать курсор не у самого края
opt.timeoutlen = 400          -- время ожидания продолжения комбинации

-- Орфография: русский + английский
opt.spell = true
opt.spelllang = { "ru", "en_us" }
-- личный словарь: слова, добавленные через zg, попадают сюда
opt.spellfile = vim.fn.stdpath("config") .. "/spell/personal.utf-8.add"

-- Красивый markdown только в текстовых файлах (скрывает служебную разметку)
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "text" },
  callback = function()
    vim.opt_local.conceallevel = 2
  end,
})

-- 3. Установка менеджера плагинов lazy.nvim (ставится сам при первом запуске)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- 4. Плагины
require("lazy").setup({

  {
    "rebelot/kanagawa.nvim",
    priority = 1000,
    config = function()
      if vim.env.TERM == "linux" then
        -- голая консоль: доступно только 16 цветов
        vim.opt.termguicolors = false
        vim.cmd.colorscheme("habamax")   -- встроенная тема, аккуратно смотрится в 16 цветах
      else
        vim.opt.termguicolors = true
        vim.cmd.colorscheme("kanagawa-wave")
      end
    end,
  },
  -- Режим фокуса: центрированный текст, всё лишнее скрыто
  {
    "folke/zen-mode.nvim",
    opts = {
      window = { width = 80, options = { number = false } },
      plugins = { options = { laststatus = 0 } },
    },
  },

  -- Затемняет всё, кроме текущего абзаца
  { "folke/twilight.nvim", opts = {} },

  -- Подсветка синтаксиса, в т.ч. markdown (новая ветка main)
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    config = function()
      -- установить нужные парсеры
      require("nvim-treesitter").install({ "markdown", "markdown_inline", "lua" })
      -- включать подсветку для нужных типов файлов
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "markdown", "text", "lua" },
        callback = function()
          pcall(vim.treesitter.start)
        end,
      })
    end,
  },
  -- Поиск по файлам и заметкам
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Найти файл" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>",  desc = "Поиск по тексту" },
    },
  },

  -- ИИ: gp.nvim (переписывание, вычитка, чат прямо в буфере)
  {
    "robitx/gp.nvim",
    config = function()
      require("gp").setup({
        providers = {
          -- достаточно задать ключ того провайдера, которым пользуешься
          openai    = { secret = os.getenv("OPENAI_API_KEY") },
          anthropic = { secret = os.getenv("ANTHROPIC_API_KEY") },
        },
        -- своя команда :GpProofread — вычитка с сохранением стиля
        hooks = {
          Proofread = function(gp, params)
            local template = "Ты внимательный редактор. Исправь орфографию, "
              .. "пунктуацию и грамматику в тексте ниже. Сохрани авторский "
              .. "стиль, интонацию и смысл. Верни только исправленный текст, "
              .. "без комментариев.\n\n{{selection}}"
            gp.Prompt(params, gp.Target.rewrite, gp.get_command_agent(), template)
          end,
        },
      })
    end,
  },

}, {
  ui = { border = "rounded" },
})

-- 5. Горячие клавиши (все начинаются с пробела)
local map = vim.keymap.set

map("n", "<leader>z",  "<cmd>ZenMode<cr>",   { desc = "Режим фокуса" })
map("n", "<leader>ts", "<cmd>set spell!<cr>", { desc = "Вкл/выкл орфографию" })
-- z= (варианты замены слова) и zg (добавить в словарь) работают по умолчанию

-- ИИ
map({ "n", "v" }, "<leader>ar", ":GpRewrite<cr>",   { desc = "ИИ: переписать" })
map("v",          "<leader>ap", ":GpProofread<cr>", { desc = "ИИ: вычитать" })
map({ "n", "v" }, "<leader>ac", ":GpChatNew<cr>",   { desc = "ИИ: новый чат" })
