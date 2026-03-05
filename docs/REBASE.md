# Git Rebase

## 1. Что такое rebase в одном предложении

`git rebase` — это операция **перебазирования**, которая берёт цепочку коммитов и **пересоздаёт их поверх другого базового коммита**, формируя линейную историю без merge-коммитов.

```
git merge  = «Слияние рек» — два потока объединяются в один через merge-коммит
git rebase = «Пересадка ветки» — коммиты снимаются и воспроизводятся на новом основании
```

---

## 2. Ключевая идея: зачем нужен rebase

### Проблема: «грязная» история при merge

Когда вы работаете в feature-ветке, а `main` уходит вперёд, `git merge` создаёт merge-коммит:

```
До merge:
    A --- B --- C --- D        ← main
          \
           E --- F --- G       ← feature

git merge main (из feature):
    A --- B --- C --- D        ← main
          \             \
           E --- F --- G --- M ← feature (M = merge-коммит)
```

Если мержить часто, история превращается в паутину, в которой трудно разобраться.

### Решение: rebase

```
До rebase:
    A --- B --- C --- D        ← main
          \
           E --- F --- G       ← feature

git rebase main (из feature):
    A --- B --- C --- D              ← main
                      \
                       E' --- F' --- G'  ← feature

E', F', G' — это НОВЫЕ коммиты с новыми SHA-1,
но с тем же содержимым (diff), что и E, F, G.
```

История становится **линейной**: выглядит так, будто feature-ветка была создана от последнего коммита `main`.

---

## 3. Механизм работы: пошагово

Когда вы выполняете `git rebase main` из ветки `feature`, Git делает следующее:

### Шаг 1: Найти общего предка (merge-base)

```bash
git merge-base feature main
# → коммит B
```

```
    A --- B --- C --- D    ← main
          ↑
     merge-base
          \
           E --- F --- G   ← feature (HEAD)
```

### Шаг 2: Вычислить diff каждого коммита feature (относительно предка)

Git формирует список коммитов, которых нет в `main`:

```
Список «патчей» для пересадки:
  1. E (diff B→E)
  2. F (diff E→F)
  3. G (diff F→G)
```

По сути, это то же самое, что:
```bash
git log main..feature --reverse
```

### Шаг 3: Переместить HEAD на целевую ветку

```bash
# Git внутренне делает:
git checkout D    # HEAD теперь на вершине main (detached HEAD)
```

```
    A --- B --- C --- D    ← main, HEAD (detached)
          \
           E --- F --- G   ← feature (пока ещё указывает сюда)
```

### Шаг 4: Последовательно применить каждый патч (cherry-pick)

```
Применяем E → создаётся E':
    A --- B --- C --- D --- E'    ← HEAD
          \
           E --- F --- G          ← feature

Применяем F → создаётся F':
    A --- B --- C --- D --- E' --- F'    ← HEAD
          \
           E --- F --- G                 ← feature

Применяем G → создаётся G':
    A --- B --- C --- D --- E' --- F' --- G'    ← HEAD
          \
           E --- F --- G                        ← feature
```

### Шаг 5: Переместить указатель ветки

```bash
# Git обновляет refs/heads/feature на G'
```

```
    A --- B --- C --- D --- E' --- F' --- G'    ← feature (HEAD)
                      ↑
                     main

Старые коммиты E, F, G больше не достижимы из feature,
но ещё живут в .git/objects и в reflog.
```

---

## 4. Что происходит внутри `.git`

### 4.1. Создание новых commit-объектов

Каждый «пересаженный» коммит — это **полностью новый объект** в `.git/objects/`:

```
Оригинальный коммит E:             Пересозданный коммит E':
┌─────────────────────┐            ┌─────────────────────┐
│ tree: T_E           │            │ tree: T_E'          │  ← Новый tree (может совпадать
│ parent: B           │            │ parent: D           │     или отличаться)
│ author: Pavel ...   │            │ author: Pavel ...   │  ← Author сохраняется!
│ committer: Pavel .. │            │ committer: Pavel .. │  ← Committer обновляется
│                     │            │                     │     (текущее время)
│ "Add login page"    │            │ "Add login page"    │  ← Сообщение сохраняется
└─────────────────────┘            └─────────────────────┘
```

**Важно:** у E' другой `parent` → другой SHA-1 → это полностью другой объект.

Даже если diff идентичен, коммит получает новый хеш, потому что:
- `parent` изменился (был B, стал D)
- `tree` может измениться (если в D были изменения, затрагивающие те же файлы)
- `committer` timestamp обновляется

### 4.2. Обновление ссылки ветки

```bash
# До rebase:
cat .git/refs/heads/feature
# → <sha1-of-G>

# После rebase:
cat .git/refs/heads/feature
# → <sha1-of-G'>
```

### 4.3. Reflog сохраняет историю

```bash
git reflog feature
# <sha1-G'> feature@{0}: rebase (finish): refs/heads/feature onto <sha1-D>
# <sha1-F'> feature@{1}: rebase (pick): Add login styles
# <sha1-E'> feature@{2}: rebase (pick): Add login page
# <sha1-D>  feature@{3}: rebase (start): checkout main
# <sha1-G>  feature@{4}: commit: Fix login tests
```

---

## 5. Конфликты при rebase

При пересадке каждого коммита может возникнуть конфликт. В отличие от merge, где конфликт один, при rebase конфликтов может быть **столько, сколько коммитов пересаживается**.

### Процесс разрешения конфликта

```
Пересаживаем E на D → КОНФЛИКТ!

    A --- B --- C --- D --- ???    ← HEAD (в процессе rebase)
          \
           E --- F --- G           ← feature (ожидает)
```

```bash
# 1. Git останавливается и сообщает о конфликте
Auto-merging login.py
CONFLICT (content): Merge conflict in login.py
error: could not apply <sha1-E>... Add login page
hint: Resolve all conflicts manually, mark them as resolved with
hint: "git add <pathspec>" then run "git rebase --continue"

# 2. Разрешаем конфликт в файле
vim login.py     # Редактируем, убираем маркеры <<<<<<<, =======, >>>>>>>

# 3. Добавляем в индекс
git add login.py

# 4. Продолжаем rebase
git rebase --continue
# Git создаёт E' и переходит к применению F
```

### Три варианта действий при конфликте

| Действие | Команда | Результат |
|----------|---------|-----------|
| Продолжить | `git rebase --continue` | Создаёт текущий коммит и переходит к следующему |
| Пропустить коммит | `git rebase --skip` | Текущий коммит не включается в результат |
| Отменить rebase | `git rebase --abort` | Полный откат к состоянию до начала rebase |

### Временные файлы при rebase

Во время rebase Git создаёт временную директорию:

```
.git/rebase-merge/          ← или .git/rebase-apply/
├── head-name               # refs/heads/feature
├── onto                    # SHA-1 коммита, на который пересаживаем (D)
├── orig-head               # SHA-1 исходного HEAD (G)
├── git-rebase-todo         # Оставшиеся коммиты для применения
├── done                    # Уже применённые коммиты
├── message                 # Сообщение текущего коммита
└── ...
```

Эта директория удаляется после успешного завершения rebase (или `--abort`).

---

## 6. `git rebase --onto`: трёхточечный rebase

Иногда нужно пересадить не всю ветку, а только часть коммитов. Для этого существует `--onto`.

### Синтаксис

```bash
git rebase --onto <новое_основание> <старое_основание> <ветка>
```

Это значит: **«Возьми коммиты от `<старое_основание>` до `<ветка>` и пересади их на `<новое_основание>`»**.

### Пример 1: Перенос ветки с одной базы на другую

```
Ситуация: feature-2 была создана от feature-1, но нужно перенести её на main.

    A --- B --- C                     ← main
          \
           D --- E                    ← feature-1
                  \
                   F --- G --- H      ← feature-2

git rebase --onto main feature-1 feature-2:

    A --- B --- C                     ← main
          |     \
          |      F' --- G' --- H'     ← feature-2
          \
           D --- E                    ← feature-1

Только F, G, H были пересажены (коммиты после feature-1).
D и E остались в feature-1.
```

### Пример 2: Удаление коммитов из середины ветки

```
Ситуация: нужно удалить коммиты C и D из ветки.

    A --- B --- C --- D --- E --- F    ← feature

git rebase --onto B D feature:

    A --- B --- E' --- F'              ← feature

Коммиты C и D исключены: пересажены только те,
что были ПОСЛЕ D (т.е. E и F).
```

### Диаграмма логики `--onto`

```
git rebase --onto <newbase> <upstream> <branch>

            НЕ пересаживаются         Пересаживаются
          ┌───────────────────┐   ┌──────────────────────┐
          │                   │   │                      │
    ... ──┤── upstream ──...──┤──►│── коммиты ── branch  │
          │                   │   │                      │
          └───────────────────┘   └──────┬───────────────┘
                                         │
                                         ▼  помещаются на
                                     newbase
```

---

## 7. Interactive Rebase (`git rebase -i`)

Интерактивный rebase — один из самых мощных инструментов Git. Он позволяет **редактировать, переупорядочивать, объединять и удалять коммиты**.

### Запуск

```bash
# Интерактивный rebase последних 4 коммитов
git rebase -i HEAD~4

# Интерактивный rebase от конкретного коммита
git rebase -i abc1234

# Интерактивный rebase относительно main
git rebase -i main
```

### Экран редактирования (todo-list)

Git открывает редактор с файлом `.git/rebase-merge/git-rebase-todo`:

```
pick a1b2c3d Add user model
pick e4f5a6b Add user controller
pick 1234567 Fix typo in model
pick 89abcde Add user tests

# Rebase 0123456..89abcde onto 0123456 (4 commands)
#
# Commands:
# p, pick   = use commit
# r, reword = use commit, but edit the commit message
# e, edit   = use commit, but stop for amending
# s, squash = use commit, but meld into previous commit
# f, fixup  = like "squash", but discard this commit's log message
# d, drop   = remove commit
# x, exec   = run command (the rest of the line) using shell
# b, break  = stop here (continue rebase later with 'git rebase --continue')
```

### Команды interactive rebase

| Команда | Описание | Пример использования |
|---------|----------|---------------------|
| `pick` (p) | Оставить коммит как есть | Обычный порядок |
| `reword` (r) | Изменить сообщение коммита | Исправить опечатку в описании |
| `edit` (e) | Остановиться для редактирования | Разделить коммит на несколько |
| `squash` (s) | Объединить с предыдущим (сохраняя оба сообщения) | Слить мелкие коммиты |
| `fixup` (f) | Объединить с предыдущим (выбросив сообщение) | Вобрать fix в основной коммит |
| `drop` (d) | Удалить коммит | Убрать ненужные изменения |
| `exec` (x) | Выполнить shell-команду | Запуск тестов после каждого коммита |
| `break` (b) | Остановиться (продолжить через `--continue`) | Промежуточная проверка |

### Пример: squash нескольких коммитов

```
Исходная история:
    A --- B --- C --- D --- E    ← feature
          │     │     │     │
      "Add"  "Fix"  "Fix"  "Add tests"
              typo   bug

Хотим объединить B, C, D в один коммит.
```

```bash
git rebase -i A    # Или git rebase -i HEAD~4
```

В редакторе меняем:

```
pick b1b1b1b Add feature
squash c2c2c2c Fix typo
squash d3d3d3d Fix bug
pick e4e4e4e Add tests
```

Git откроет ещё один редактор для объединённого сообщения:

```
# This is a combination of 3 commits.
# This is the 1st commit message:
Add feature

# This is the commit message #2:
Fix typo

# This is the commit message #3:
Fix bug
```

Результат:

```
    A --- BCD' --- E'    ← feature

BCD' содержит изменения B+C+D с объединённым сообщением.
E' — пересозданный коммит E (новый parent → новый SHA-1).
```

### Пример: переупорядочивание коммитов

Просто поменяйте строки местами в редакторе:

```
# Было:
pick a1a1a1a Add user model
pick b2b2b2b Add user controller
pick c3c3c3c Add tests
pick d4d4d4d Add docs

# Стало (сначала тесты, потом контроллер):
pick a1a1a1a Add user model
pick c3c3c3c Add tests
pick b2b2b2b Add user controller
pick d4d4d4d Add docs
```

⚠️ Переупорядочивание может привести к конфликтам, если коммиты зависят друг от друга.

### Пример: разделение коммита с `edit`

```bash
git rebase -i HEAD~3
```

```
edit a1a1a1a Add model and controller    # ← хотим разделить этот коммит
pick b2b2b2b Add tests
pick c3c3c3c Add docs
```

Git остановится на коммите `a1a1a1a`:

```bash
# Откатываем коммит, но сохраняем изменения в Working Tree
git reset HEAD~1

# Добавляем и коммитим по частям
git add model.py
git commit -m "Add model"

git add controller.py
git commit -m "Add controller"

# Продолжаем rebase
git rebase --continue
```

### Пример: exec для запуска тестов

```
pick a1a1a1a Add user model
exec python -m pytest tests/
pick b2b2b2b Add user controller
exec python -m pytest tests/
pick c3c3c3c Add integration tests
exec python -m pytest tests/
```

Или автоматически после каждого коммита:

```bash
git rebase -i HEAD~5 --exec "python -m pytest tests/"
```

Если тесты падают на каком-то коммите, rebase останавливается, и вы можете исправить проблему.

---

## 8. `--autosquash`: автоматическое упорядочивание fixup-коммитов

Если вы используете конвенцию именования коммитов `fixup!` или `squash!`, Git может автоматически расставить команды в интерактивном rebase.

### Рабочий процесс

```bash
# 1. Основной коммит
git commit -m "Add login feature"

# 2. Позже нашли баг — создаём fixup-коммит
git commit --fixup=<sha1-of-"Add login feature">
# Сообщение автоматически будет: "fixup! Add login feature"

# 3. Ещё позже — ещё один фикс
git commit --fixup=<sha1-of-"Add login feature">
# Сообщение: "fixup! Add login feature"

# 4. Запускаем interactive rebase с --autosquash
git rebase -i --autosquash main
```

Git автоматически переупорядочит todo-list:

```
pick a1a1a1a Add login feature
fixup c3c3c3c fixup! Add login feature      ← автоматически подставлено
fixup d4d4d4d fixup! Add login feature      ← и упорядочено
pick b2b2b2b Add dashboard feature
```

> 💡 Можно включить `--autosquash` по умолчанию:
> ```bash
> git config --global rebase.autosquash true
> ```

---

## 9. Rebase vs Merge: детальное сравнение

```
                     git merge                           git rebase
               ┌──────────────────┐             ┌────────────────────────┐
               │                  │             │                        │
  До:  A─B─C   │  A─B───C        │             │  A─B─C                 │
        \      │   \ \  │        │             │       \                │
         D─E   │    D─E─M        │             │        D'─E'           │
               │        ↑ merge  │             │            ↑ feature   │
               │                  │             │                        │
  История:     │  Нелинейная      │             │  Линейная              │
  Доп. коммиты:│  Merge-коммит    │             │  Нет                   │
  SHA коммитов:│  Сохранены       │             │  Изменены (D→D', E→E') │
               └──────────────────┘             └────────────────────────┘
```

### Подробная таблица сравнения

| Аспект | `git merge` | `git rebase` |
|--------|-------------|--------------|
| **История** | Нелинейная (граф) | Линейная |
| **Merge-коммиты** | Создаются | Не создаются |
| **SHA-1 коммитов** | Сохраняются | Пересоздаются (новые SHA) |
| **Конфликты** | Один раз | Может быть на каждом коммите |
| **Безопасность** | ✅ Безопасен для shared-веток | ⚠️ Опасен для shared-веток |
| **Трассируемость** | Видно, когда и что мержили | Не видно, что была отдельная ветка |
| **Простота отмены** | `git revert -m 1` | Сложнее (нужен reflog) |
| **Требует `--force` при push** | ❌ Нет | ✅ Да (если ветка уже была запушена) |

---

## 10. ⚡ Главная опасность: rebase опубликованных коммитов

### Проблема

```
Ваш локальный репозиторий и origin:
    A --- B --- C --- D    ← feature, origin/feature
                      ↑
                 Маша работает поверх D

Вы делаете rebase на main:
    A --- B --- E --- F --- C' --- D'    ← feature (локально)
                ↑                         (новые SHA!)
               main

git push --force origin feature    ← ⚠️ Перезаписали историю!
```

### Что происходит у Маши

```
У Маши (до вашего force push):
    A --- B --- C --- D --- G --- H    ← feature (Маша добавила G и H)

После git fetch:
    A --- B --- C --- D --- G --- H     ← feature (локальная)
                ↑
          origin/feature (старая)

    A --- B --- E --- F --- C' --- D'   ← origin/feature (новая)

Git pull → КОНФЛИКТ ИСТОРИИ!
  → Коммиты C и D дублируются (C, D и C', D')
  → Маша получает хаос в истории
  → Коммиты G и H «повисают» относительно новой истории
```

### Золотое правило

> **Никогда не делайте rebase коммитов, которые уже были запушены в shared-репозиторий**, если другие люди могут на них основывать свою работу.

### Когда rebase безопасен

| Ситуация | Безопасен? | Почему |
|----------|-----------|--------|
| Локальные коммиты (не пушили) | ✅ Да | Никто их не видел |
| Персональная feature-ветка | ✅ Да | Только вы работаете |
| После push, но до review | ⚠️ Осторожно | Нужен `--force-with-lease` |
| Shared-ветка (`main`, `develop`) | ❌ Нет | Сломает работу всей команде |

### `--force-with-lease`: безопасный force push

```bash
# Вместо:
git push --force origin feature      # ❌ Опасно! Перезапишет чужие коммиты

# Используйте:
git push --force-with-lease origin feature   # ✅ Безопасно! Проверяет, что origin не изменился
```

`--force-with-lease` откажет в push, если кто-то успел запушить свои коммиты в эту ветку после вашего последнего fetch.

---

## 11. Типовые рабочие процессы с rebase

### 11.1. Обновление feature-ветки перед merge

```bash
# Находимся в feature
git checkout feature

# Получаем обновления main
git fetch origin
git rebase origin/main

# Если были конфликты — разрешаем
# ...
git rebase --continue

# Push с обновлённой историей (ветка только наша)
git push --force-with-lease origin feature

# Теперь merge в main будет fast-forward!
git checkout main
git merge feature    # ← чистый fast-forward, без merge-коммита
```

```
До rebase:                          После rebase + merge:
    A --- B --- C       ← main         A --- B --- C --- E' --- F'  ← main, feature
          \                                           (линейная история!)
           E --- F      ← feature
```

### 11.2. Pull с rebase вместо merge

```bash
# Вместо:
git pull origin main            # Создаёт merge-коммит при расхождении

# Используйте:
git pull --rebase origin main   # Пересаживает ваши коммиты поверх origin/main
```

Можно включить по умолчанию:

```bash
git config --global pull.rebase true
```

### 11.3. Очистка истории перед PR (Pull Request)

```bash
# Посмотрим, сколько коммитов в ветке
git log main..feature --oneline
# abc1234 Fix test
# def5678 Add feature
# 111aaaa WIP
# 222bbbb Fix lint
# 333cccc Initial implementation

# Объединим и причешем перед отправкой на review
git rebase -i main
```

```
pick 333cccc Initial implementation
squash 222bbbb Fix lint
squash 111aaaa WIP
pick def5678 Add feature
fixup abc1234 Fix test
```

Результат — чистая история из 2 логичных коммитов вместо 5 «рабочих».

---

## 12. Внутреннее устройство: подробный разбор

### 12.1. Как Git определяет коммиты для rebase

```bash
git rebase main    # Из ветки feature
```

Внутри Git выполняет:

```bash
# 1. Находит merge-base
mb=$(git merge-base feature main)

# 2. Получает список коммитов для пересадки
git rev-list --reverse $mb..feature
# → E, F, G (коммиты, которых нет в main)

# 3. Для каждого коммита формирует патч
git format-patch $mb..feature
```

### 12.2. Пересоздание коммита (внутренний cherry-pick)

Для каждого коммита Git выполняет аналог cherry-pick:

```bash
# Для коммита E:

# 1. Вычисляет three-way merge:
#    base  = parent(E) = B     (дерево файлов родителя E)
#    ours  = HEAD              (текущая вершина, начиная с D)
#    theirs = E                (дерево файлов коммита E)

# 2. Выполняет three-way merge
#    Результат = HEAD + (E - B)
#    Т.е. текущее состояние + те изменения, что вносил коммит E

# 3. Если нет конфликтов — создаёт новый коммит E':
git commit-tree <tree> -p <HEAD> -m "<сообщение E>"
# → новый SHA-1 для E'

# 4. HEAD перемещается на E'
```

### 12.3. Three-way merge при rebase

```
        BASE (parent исходного коммита)
       /           \
      /             \
   OURS (HEAD)    THEIRS (исходный коммит)
      \             /
       \           /
        РЕЗУЛЬТАТ
```

Для каждого файла:
- Если файл изменён только в THEIRS → берём версию THEIRS
- Если файл изменён только в OURS → берём версию OURS
- Если файл изменён в обоих → **конфликт** (или автослияние, если изменения не пересекаются)

---

## 13. Специальные флаги rebase

### `--keep-empty`

По умолчанию rebase пропускает пустые коммиты (где diff пуст). Этот флаг сохраняет их:

```bash
git rebase --keep-empty main
```

### `--rebase-merges` (замена устаревшего `--preserve-merges`)

Пересаживает ветку, **сохраняя структуру merge-коммитов**:

```bash
git rebase --rebase-merges main
```

```
До:
    A --- B --- C           ← main
          \
           D --- M --- G    ← feature
                /
           E --             ← topic

git rebase --rebase-merges main:

    A --- B --- C                ← main
                \
                 D' --- M' --- G'  ← feature
                       /
                 E' --             (merge-структура сохранена!)
```

### `--committer-date-is-author-date`

Сохраняет дату коммиттера равной дате автора (чтобы не менялись даты):

```bash
git rebase --committer-date-is-author-date main
```

### `--no-ff` (no fast-forward)

Пересоздаёт все коммиты, даже если rebase мог бы быть fast-forward:

```bash
git rebase --no-ff main
```

Это полезно, когда нужно получить новые SHA-1 для всех коммитов (например, чтобы повторно влить отменённый revert).

---

## 14. Отмена rebase

### Вариант 1: `git rebase --abort` (во время rebase)

Если вы в процессе rebase и хотите отменить:

```bash
git rebase --abort
# Состояние полностью восстанавливается к тому, что было до начала rebase
```

### Вариант 2: `git reflog` + `git reset` (после завершения rebase)

```bash
# Смотрим reflog
git reflog
# abc1234 HEAD@{0}: rebase (finish): refs/heads/feature onto def5678
# ...
# 999aaaa HEAD@{5}: commit: Last commit before rebase

# Откатываемся
git reset --hard 999aaaa
# или
git reset --hard feature@{1}    # Предыдущее состояние feature
```

### Вариант 3: `ORIG_HEAD`

Git сохраняет предыдущее значение HEAD в `ORIG_HEAD` перед «опасными» операциями:

```bash
# Сразу после rebase
git reset --hard ORIG_HEAD
```

⚠️ Работает только до следующей операции, которая обновит `ORIG_HEAD` (merge, rebase, reset).

---

## 15. Сравнение: Rebase, Merge, Cherry-pick

```
┌─────────────┬─────────────────┬──────────────────┬───────────────────┐
│             │   git merge     │   git rebase     │  git cherry-pick  │
├─────────────┼─────────────────┼──────────────────┼───────────────────┤
│ Что делает  │ Объединяет две  │ Пересаживает     │ Копирует один     │
│             │ ветки через     │ цепочку коммитов │ коммит на текущую │
│             │ merge-коммит    │ на новое         │ ветку             │
│             │                 │ основание        │                   │
├─────────────┼─────────────────┼──────────────────┼───────────────────┤
│ Создаёт     │ Merge-коммит    │ Новые коммиты    │ Новый коммит      │
│             │ (2+ родителей)  │ (с новыми SHA)   │ (с новым SHA)     │
├─────────────┼─────────────────┼──────────────────┼───────────────────┤
│ История     │ Сохраняет       │ Переписывает     │ Не переписывает   │
│             │ полностью       │ (линеаризует)    │ (добавляет)       │
├─────────────┼─────────────────┼──────────────────┼───────────────────┤
│ Безопасность│ ✅ Безопасен    │ ⚠️ Осторожно     │ ✅ Безопасен      │
│ для shared  │                 │                  │                   │
├─────────────┼─────────────────┼──────────────────┼───────────────────┤
│ Кол-во      │ Макс. 1         │ По числу         │ Макс. 1           │
│ конфликтов  │                 │ коммитов         │                   │
└─────────────┴─────────────────┴──────────────────┴───────────────────┘
```

---

## 16. Итоговая шпаргалка

```
┌────────────────────────────────────────────────────────────────┐
│               ХОЧУ ИНТЕГРИРОВАТЬ ИЗМЕНЕНИЯ                    │
│                                                                │
│      Ветка shared (main/develop)?                              │
│      ┌───────┴───────┐                                         │
│     Да              Нет                                        │
│      │               │                                         │
│  git merge      Хочу линейную историю?                         │
│                 ┌────────┴────────┐                             │
│                Да                Нет                            │
│                 │                 │                             │
│           git rebase         git merge                         │
│                                                                │
│                                                                │
│           ХОЧУ ПРИЧЕСАТЬ ИСТОРИЮ                               │
│                                                                │
│      Коммиты уже запушены?                                     │
│      ┌───────┴───────┐                                         │
│     Да              Нет                                        │
│      │               │                                         │
│  ⚠️ Только если     git rebase -i                              │
│  ветка только ваша                                             │
│  + force-with-lease                                            │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Команды в одном месте

```bash
# Базовый rebase
git rebase main                          # Пересадить текущую ветку на main

# Интерактивный rebase
git rebase -i HEAD~5                     # Редактировать последние 5 коммитов
git rebase -i main                       # Редактировать все коммиты ветки

# Rebase --onto
git rebase --onto main feature-1 feature-2  # Пересадить часть коммитов

# Управление конфликтами
git rebase --continue                    # Продолжить после разрешения конфликта
git rebase --skip                        # Пропустить текущий коммит
git rebase --abort                       # Отменить весь rebase

# Pull с rebase
git pull --rebase origin main            # Pull + rebase вместо merge

# Безопасный push после rebase
git push --force-with-lease origin feature  # Не перезапишет чужие коммиты

# Отмена rebase
git reset --hard ORIG_HEAD               # Вернуть всё как было
git reflog                               # Найти нужный коммит в истории
```

---

> **Главное правило rebase:** Используйте rebase для наведения порядка в **своей локальной** истории перед публикацией. Для **публичной** истории используйте merge. Rebase — это инструмент **чистописания**, а не **совместной работы**. ✍️
