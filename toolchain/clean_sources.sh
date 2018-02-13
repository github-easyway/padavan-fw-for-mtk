#!/bin/bash

echo "=================REMOVE-OLD-BUILD-TREE=================="
[ -d build ] && rm -rf build
[ -d out ] && rm -rf out
echo "====================All IS DONE!========================"
