# InputPrimary

一个极简的 macOS 菜单栏工具：切换到某个应用时，自动切换到为它指定的输入法。不显示任何输入法提示浮窗。

## 构建

```sh
./build.sh            # 生成 build/InputPrimary.app
./build.sh --install  # 同时安装到 /Applications 并启动
```

需要 Xcode Command Line Tools，macOS 13+。

图标由 `Scripts/make-icon.swift` 绘制，修改后运行 `swift Scripts/make-icon.swift Resources/AppIcon.icns` 重新生成。

## 使用

点击菜单栏的键盘图标：

- **“某应用” 使用**：为当前前台应用指定输入法（“跟随默认”即删除该应用的规则）
- **其他应用默认使用**：没有规则的应用统一切换到的输入法（“不切换”则保持不动）
- **已设置的应用**：查看、修改或删除已有规则
- **登录时启动**：建议先 `--install` 到 /Applications 再开启

规则保存在 `defaults read local.inputprimary`。

## License

[MIT](LICENSE)
