#!/bin/bash
# 开发版运行脚本，自动使用 dev flavor
flutter run --flavor dev --dart-define=dev=true "$@"
