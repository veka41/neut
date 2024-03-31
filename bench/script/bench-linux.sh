#!/bin/zsh

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)

for target_dir in $(find "$SCRIPT_DIR/../action" -maxdepth 1 -mindepth 1 -type d | sort); do
  cd $target_dir
  stack install --local-bin-path ./bin
  $NEUT build --install ./bin
  size=$(cat ./test-size.txt)
  step=10
  for executable in $(find $target_dir/bin -type f | sort); do
    echo ${executable:t}
    mkdir -p ../../result/json/$PLATFORM
    hyperfine -r 3 -P SIZE $((size/step)) $size -D $((size/step)) "${executable} {SIZE}" --export-json ../../result/json/$PLATFORM/${executable:t}.json
  done
done
