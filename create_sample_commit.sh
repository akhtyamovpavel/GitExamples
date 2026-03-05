#!/bin/bash

commit=$1
echo "$commit" > assets/${commit}.md
git add assets/${commit}.md

git commit -m "Added $commit"
