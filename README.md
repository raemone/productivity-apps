# productivity-apps

Small, self-contained productivity tools. One folder per app under `apps/`, each
free to use whatever stack suits it — a PowerShell tray app, a single HTML file,
a Vite project, a Python CLI. There is no shared build at the root and no
monorepo tooling to fight with: `git clone` and each app runs on its own terms.

## Apps

| App | What it does | Stack | Platform |
| --- | --- | --- | --- |
| [lid-keeper](apps/lid-keeper) | Tray toggle for what Windows does when you close the laptop lid: stay awake or sleep | PowerShell + Windows Forms | Windows 10/11 |

## Layout

```
apps/
  <app-name>/          one app, one folder, kebab-case
    README.md          what it does, how to run it, how it works
    src/               the code
    install/           optional setup and removal scripts
  _template/           starting point for a new app
.github/workflows/     per-stack CI, added as apps need it
```

## Adding an app

1. Copy `apps/_template` to `apps/<app-name>`.
2. Fill in its `README.md` — what it does, how to run it, what it changes on the
   machine, how to remove it.
3. Add a row to the table above.
4. If the app's language has no CI yet, add a workflow that only runs on changes
   under that app's path.

Conventions that keep a mixed-stack repo workable:

- **Each app documents its own prerequisites.** Nobody should need to read the
  root README to run one app.
- **An app owns its dependencies.** No root `package.json`, no shared lockfile.
- **Say what an app changes outside its folder.** System settings, scheduled
  tasks, registry keys, autostart entries — list them, and ship a way to undo
  them.
- **Prefer what is already on the machine.** A tool that needs no install gets
  used; one that needs a toolchain gets opened once.

## Licence

MIT — see [LICENSE](LICENSE).
