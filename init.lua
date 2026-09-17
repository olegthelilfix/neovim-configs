-- ~/.config/nvim/init.lua
-- Конфиг Neovim для писательства:
-- русская орфография, режим фокуса, markdown, ИИ.

-- 1. Лидер-клавиша (задаётся ДО загрузки плагинов)
vim.g.mapleader = " "        -- пробел как основная лидер-клавиша
vim.g.maplocalleader = " "

-- 2. Базовые настройки под прозу
local opt = vim.opt
opt.number = true             -- номера строк
opt.wrap = true               -- переносить длинные строки
opt.linebreak = true          -- переносить по словам, а не по буквам
opt.breakindent = true        -- сохранять отступ при переносе
opt.showbreak = "↳ "          -- маркер переноса
opt.mouse = "a"               -- мышь, если терминал её поддерживает
opt.clipboard = "unnamedplus" -- общий системный буфер (нужен xclip/wl-clipboard)
opt.termguicolors = true      -- 24-битный цвет (нужен современный терминал)
opt.scrolloff = 999           -- «печатная машинка»: текущая строка всегда по центру
opt.timeoutlen = 400          -- время ожидания продолжения комбинации
opt.updatetime = 1000         -- через сколько простоя срабатывает автосохранение

-- Русская раскладка в командах: в НОРМАЛЬНОМ режиме команды работают,
-- даже если включена русская раскладка ОС (фыва → asdf и т.д.).
-- На текст в режиме вставки не влияет.
opt.langmap =
  "ФИСВУАПРШОЛДЬТЩЗЙКЫЕГМЦЧНЯ;ABCDEFGHIJKLMNOPQRSTUVWXYZ," ..
  "фисвуапршолдьтщзйкыегмцчня;abcdefghijklmnopqrstuvwxyz"

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

-- Автосохранение: пишем файл при простое, выходе из вставки и потере фокуса.
-- Пишется только настоящий именованный файл с несохранёнными правками.
local function autosave()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].modified
    and vim.bo[buf].buftype == ""
    and vim.api.nvim_buf_get_name(buf) ~= ""
    and vim.bo[buf].modifiable
  then
    vim.cmd("silent! write")
  end
end

vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "FocusLost", "BufLeave" }, {
  callback = autosave,
})

-- 2.1 Помощники для статусной панели (статистика системы)
-- Заряд батареи читается из sysfs и кэшируется, обновляясь раз в 30 секунд.
local sys = { battery = "" }

-- прочитать первую строку файла, вернуть nil если файла нет
local function read_first_line(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local line = f:read("l")
  f:close()
  return line
end

-- найти батарею в sysfs (обычно BAT0, иногда BAT1)
local function find_battery_path()
  for _, name in ipairs({ "BAT0", "BAT1", "BAT2" }) do
    local base = "/sys/class/power_supply/" .. name
    if read_first_line(base .. "/capacity") then
      return base
    end
  end
  return nil
end

-- перевести часы (дробные) в «Nч Mм»
local function fmt_hours(h)
  if not h or h <= 0 then return nil end
  local total_min = math.floor(h * 60 + 0.5)
  local hh = math.floor(total_min / 60)
  local mm = total_min % 60
  if hh > 0 then
    return string.format("%dч %02dм", hh, mm)
  end
  return string.format("%dм", mm)
end

-- оценить оставшееся время из sysfs
-- (energy_now/power_now — в мкВт·ч/мкВт, либо charge_now/current_now — в мкА·ч/мкА)
local function battery_time(base, charging)
  local energy = tonumber(read_first_line(base .. "/energy_now"))
    or tonumber(read_first_line(base .. "/charge_now"))
  local power = tonumber(read_first_line(base .. "/power_now"))
    or tonumber(read_first_line(base .. "/current_now"))
  local full = tonumber(read_first_line(base .. "/energy_full"))
    or tonumber(read_first_line(base .. "/charge_full"))
  if not energy or not power or power == 0 then return nil end
  local remaining
  if charging then
    if not full then return nil end
    remaining = (full - energy) / power   -- до полной зарядки
  else
    remaining = energy / power            -- до разрядки
  end
  return fmt_hours(remaining)
end

local function refresh_battery()
  -- Linux: заряд и статус лежат в /sys/class/power_supply/BATx/
  local base = find_battery_path()
  if not base then
    sys.battery = ""
    return
  end
  local pct = read_first_line(base .. "/capacity")
  local status = read_first_line(base .. "/status") or ""
  if not pct then
    sys.battery = ""
    return
  end
  local charging = (status == "Charging" or status == "Full")
  local icon = charging and "" or ""
  local time = battery_time(base, charging)
  if status == "Full" then
    sys.battery = string.format("%s %s%%", icon, pct)
  elseif time then
    sys.battery = string.format("%s %s%% (%s)", icon, pct, time)
  else
    sys.battery = string.format("%s %s%%", icon, pct)
  end
end

refresh_battery()
-- периодическое обновление заряда (30 000 мс) + перерисовка панели
local batt_timer = (vim.uv or vim.loop).new_timer()
batt_timer:start(30000, 30000, vim.schedule_wrap(function()
  refresh_battery()
  pcall(vim.cmd, "redrawstatus")
end))

-- Функции для нативной статусной строки (вызываются из 'statusline' через v:lua).
-- Статистика текста: слова и знаки (в выделении — только выделенное)
function _G.writer_stats()
  local wc = vim.fn.wordcount()
  if wc.visual_words then
    return string.format("%d сл  %d зн (выд.)", wc.visual_words, wc.visual_chars)
  end
  return string.format("%d сл  %d зн", wc.words, wc.chars)
end

-- Правый блок: статистика · батарея · дата/время
function _G.writer_status_right()
  local parts = { _G.writer_stats() }
  if sys.battery ~= "" then
    parts[#parts + 1] = sys.battery
  end
  parts[#parts + 1] = os.date("%d.%m %H:%M")
  return table.concat(parts, "   ·   ")
end

-- Текущий режим по-русски (виден в панели в любом состоянии)
local mode_names = {
  n = "НОРМ", i = "ВСТАВКА", v = "ВИЗУАЛ", V = "ВИЗУАЛ-СТР",
  ["\22"] = "ВИЗУАЛ-БЛОК", c = "КОМАНДА", R = "ЗАМЕНА",
  s = "ВЫДЕЛ", t = "ТЕРМИНАЛ", ["!"] = "ШЕЛЛ",
}
function _G.writer_mode()
  return mode_names[vim.fn.mode()] or vim.fn.mode():upper()
end

-- Фоновый авто-коммит и пуш репозитория с текстом (раз в несколько минут).
-- Работает с git-репозиторием, в котором лежит текущий файл. Отключить: :AutoGit off
vim.g.autogit_enabled = true

local function autogit()
  if not vim.g.autogit_enabled then return end
  -- сначала сохраняем все буферы
  pcall(vim.cmd, "silent! wall")
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then return end
  local dir = vim.fs.dirname(file)

  vim.system({ "git", "-C", dir, "rev-parse", "--is-inside-work-tree" }, { text = true }, function(res)
    if res.code ~= 0 then return end -- не git-репозиторий
    vim.system({ "git", "-C", dir, "status", "--porcelain" }, { text = true }, function(st)
      if (st.stdout or "") == "" then return end -- нет изменений
      local msg = "auto: " .. os.date("%Y-%m-%d %H:%M")
      vim.system({ "git", "-C", dir, "add", "-A" }, {}, function(a)
        if a.code ~= 0 then return end
        vim.system({ "git", "-C", dir, "commit", "-m", msg }, {}, function(c)
          if c.code ~= 0 then return end
          -- пуш; если нет удалёнки или нет сети — тихо игнорируем
          vim.system({ "git", "-C", dir, "push" }, { text = true }, function(p)
            if p.code ~= 0 then
              vim.schedule(function()
                vim.notify("autogit: коммит сделан, пуш не удался", vim.log.levels.WARN)
              end)
            end
          end)
        end)
      end)
    end)
  end)
end

-- запуск раз в 3 минуты (180 000 мс)
local git_timer = (vim.uv or vim.loop).new_timer()
git_timer:start(180000, 180000, vim.schedule_wrap(autogit))

-- Синхронный коммит+пуш через vim.fn.system. Возвращает строку-результат.
-- Используется и при выходе (VimLeavePre), и вручную командой :AutoGitNow.
function _G.autogit_run()
  pcall(vim.cmd, "silent! wall")
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then return "autogit: нет имени файла" end
  local dir = vim.fs.dirname(file)
  local function git(...)
    local out = vim.fn.system({ "git", "-C", dir, ... })
    return vim.v.shell_error, (out or "")
  end
  if git("rev-parse", "--is-inside-work-tree") ~= 0 then
    return "autogit: не git-репозиторий (" .. dir .. ")"
  end
  local _, status = git("status", "--porcelain")
  if status == "" then return "autogit: нет изменений" end
  git("add", "-A")
  local code, out = git("commit", "-m", "auto: " .. os.date("%Y-%m-%d %H:%M"))
  if code ~= 0 then return "autogit: commit не удался — " .. out end
  code, out = git("push")
  if code ~= 0 then return "autogit: коммит есть, push не удался — " .. out end
  return "autogit: закоммичено и запушено"
end

-- ручной запуск с показом результата/ошибки
vim.api.nvim_create_user_command("AutoGitNow", function()
  vim.notify(_G.autogit_run())
end, {})

-- Выход: vim.fn.system во время VimLeavePre обрывается, поэтому используем
-- os.execute — чистый системный вызов, не зависящий от цикла Neovim.
local autogit_log = vim.fn.stdpath("state") .. "/autogit.log"
local function autogit_exit()
  local f = io.open(autogit_log, "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S"), "  VimLeavePre\n"); f:close() end
  if not vim.g.autogit_enabled then return end
  pcall(vim.cmd, "silent! wall")
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then return end
  local dir = vim.fn.shellescape(vim.fn.fnamemodify(file, ":h"))
  -- весь блок в фигурных скобках, весь вывод — в лог (для диагностики)
  local cmd = string.format(
    "{ echo '--- exit run ---'; cd %s && git add -A "
    .. "&& git commit -m \"auto: %s\" && git push; } >>%s 2>&1",
    dir, os.date("%Y-%m-%d %H:%M"), vim.fn.shellescape(autogit_log)
  )
  os.execute(cmd)
end

vim.api.nvim_create_autocmd("VimLeavePre", { callback = autogit_exit })

-- команда :AutoGit on|off — включить/выключить фоновый коммит
vim.api.nvim_create_user_command("AutoGit", function(cmd)
  local arg = cmd.args:lower()
  if arg == "off" then
    vim.g.autogit_enabled = false
    vim.notify("autogit: выключен")
  elseif arg == "on" then
    vim.g.autogit_enabled = true
    vim.notify("autogit: включён")
  else
    vim.notify("autogit: " .. (vim.g.autogit_enabled and "включён" or "выключен"))
  end
end, { nargs = "?", complete = function() return { "on", "off" } end })

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
      window = { width = 80, options = { number = true } },  -- оставить номера строк
      plugins = { options = { laststatus = 3 } },  -- оставить статусную панель в фокусе
    },
  },

  -- Затемняет всё, кроме текущего абзаца
  { "folke/twilight.nvim", opts = {} },

  -- Подсветка синтаксиса, в т.ч. markdown (новая ветка main)
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        -- нужные парсеры ставятся автоматически
        ensure_installed = { "markdown", "markdown_inline", "lua" },
        highlight = { enable = true },
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
        hooks = {
          -- :GpProofread — вычитка с сохранением стиля
          Proofread = function(gp, params)
            local template = "Ты внимательный редактор. Исправь орфографию, "
              .. "пунктуацию и грамматику в тексте ниже. Сохрани авторский "
              .. "стиль, интонацию и смысл. Верни только исправленный текст, "
              .. "без комментариев.\n\n{{selection}}"
            gp.Prompt(params, gp.Target.rewrite, gp.get_command_agent(), template)
          end,
          -- :GpSynonyms — синонимы к выделенному слову/выражению (во всплывающем окне)
          Synonyms = function(gp, params)
            local template = "Подбери 10 синонимов на русском к слову или выражению ниже. "
              .. "Учитывай контекст, если он есть. Верни списком через запятую, "
              .. "без пояснений и нумерации.\n\n{{selection}}"
            gp.Prompt(params, gp.Target.popup, gp.get_command_agent(), template)
          end,
        },
      })
    end,
  },

}, {
  ui = { border = "rounded" },
})

-- 4.1 Нативная статусная панель (без плагина — надёжно в любом терминале)
-- Слева: файл и флаг изменения. Справа: слова/знаки · батарея · дата/время · позиция.
vim.opt.laststatus = 3   -- одна панель на всё окно
vim.opt.statusline = table.concat({
  " %{v:lua.writer_mode()} ",     -- текущий режим (НОРМ/ВСТАВКА/…)
  "  %f",                         -- имя файла
  " %m",                          -- [+] если есть несохранённые правки
  "%=",                           -- выравнивание вправо
  "%{v:lua.writer_status_right()}",
  "   ·   %l:%c ",                -- строка:столбец
})

-- 4.2 Шаблон новой главы: вставляет заголовок с датой в текущий буфер
local ru_weekdays = { "воскресенье", "понедельник", "вторник", "среда",
  "четверг", "пятница", "суббота" }
local function insert_chapter_template()
  local wday = tonumber(os.date("%w")) + 1
  local date = string.format("%s, %s", ru_weekdays[wday], os.date("%d.%m.%Y"))
  local lines = {
    "# ",
    "",
    "*" .. date .. "*",
    "",
    "",
  }
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, lines)
  -- поставить курсор после «# » в режим вставки
  vim.api.nvim_win_set_cursor(0, { row, 2 })
  vim.cmd("startinsert!")
end
vim.api.nvim_create_user_command("NewChapter", insert_chapter_template, {})

-- 5. Горячие клавиши (все начинаются с пробела)
local map = vim.keymap.set

map("n", "<leader>z",  "<cmd>ZenMode<cr>",   { desc = "Режим фокуса" })
map("n", "<leader>ts", "<cmd>set spell!<cr>", { desc = "Вкл/выкл орфографию" })
map("n", "<leader>ng", insert_chapter_template, { desc = "Новая глава (шаблон)" })
-- z= (варианты замены слова) и zg (добавить в словарь) работают по умолчанию

-- ИИ
map({ "n", "v" }, "<leader>ar", ":GpRewrite<cr>",   { desc = "ИИ: переписать" })
map("v",          "<leader>ap", ":GpProofread<cr>", { desc = "ИИ: вычитать" })
map({ "n", "v" }, "<leader>ac", ":GpChatNew<cr>",   { desc = "ИИ: новый чат" })
map("v",          "<leader>as", ":GpSynonyms<cr>",  { desc = "ИИ: синонимы" })
