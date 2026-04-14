![switchkey](README.assets/switchkey.png)

# SwitchKey

Automatically use the correct input source.

Ever hassled by wrong input source when switching application?  
SwitchKey can automatically activate your choice for you.

## Download & Install

### Manually:

Download (macOS):  
[![Latest](https://img.shields.io/badge/dynamic/json?color=brightgreen&label=latest&query=%24.tag_name&url=https%3A%2F%2Fapi.github.com%2Frepos%2Fitsuhane%2FSwitchKey%2Freleases%2Flatest&style=social)](https://github.com/itsuhane/SwitchKey/releases/latest/download/SwitchKey.zip)  
Uncompress, then drag & drop into your Applications folder.

### Via Homebrew (thanks to [@fanvinga](//github.com/fanvinga/)):

```
brew install --cask switchkey
```

### Usage

![switchkey-ui](README.assets/switchkey-ui.png)

- **添加应用 (Add App)**：点击“添加”手动选择应用，或程序会自动记录您切出的当前运行应用。
- **配置输入法 (Select Input Source)**：通过应用右侧下拉菜单，为各个应用单独指定对应的输入法。
- **启用/禁用 (Enable/Disable)**：点击右侧的开关控制是否对该应用启用自动切换。
- **删除应用 (Remove App)**：点击最右侧垃圾桶图标删除不再需要的应用配置。
- **全局设置 (Global Settings)**：
  - **默认输入法**：为新加入的应用指定默认的输入法。
  - **Shift 切换输入法**：勾选后，可单按 Shift 键快速切换系统的当前输入法。
  - **开机自启**：设置系统启动时自动运行 SwitchKey。

Not working? See below.

### First Run

Upon first launch, SwitchKey will ask for accessibility permission.  
SwitchKey will open accessibility page, **and exit**.  
After you grant permission, re-launch SwitchKey again.  
The same will happen if you reject the permission later.

![switchkey-ui](README.assets/switchkey-permission.png)

### Purchase

I wrote this because I tried some other tools.  
They are either buggy or too cumbersome to configure.  
I payed money and time for them.  
So you don't have to pay for them anymore.

### Bug Report & Feature Request

Welcome! Please click [here](https://github.com/itsuhane/SwitchKey/issues/new).
