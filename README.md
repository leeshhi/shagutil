# shagutil

## ⚠️ Backup

Currently, Shagutil doesn't automatically create a backup to ensure that all tweaks can be rolled back to their original state. Therefore, I recommend doing this manually before applying any tweaks.
**Link:** https://support.microsoft.com/en-us/topic/how-to-back-up-and-restore-the-registry-in-windows-855140ad-e318-2a13-2829-d428a2ab0692

## 💡 Usage

ShagUtil must be run in Admin mode because it performs system-wide tweaks. To achieve this, run PowerShell as an administrator. Here are a few ways to do it:

1. **Start menu Method:**
   - Right-click on the start menu.
   - Terminal (Admin).

2. **Search and Launch Method:**
   - Press the Windows key.
   - Type Terminal.
   - Press `Ctrl + Shift + Enter` or Right-click and choose "Run as administrator" to launch it with administrator privileges.

### Launch Command

#### Recommended:

```ps1
irm "https://shag.my/win" | iex
```

### Alternatives:
```ps1
irm "win.shag.my" | iex
```

## 💖 Support
- To support the project, make sure to leave a ⭐️!

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/H2H0K8V3U)

## 🏅 Special thanks to
- [ChrisTitusTech @winutil](https://github.com/ChrisTitusTech/winutil) > For some tweaks and ideas
