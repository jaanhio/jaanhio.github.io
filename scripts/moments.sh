#!/bin/bash

photo_dir="/Users/jianhao/Pictures/chubu2023"
prog_dir="/Users/jianhao/Documents/repos/jaanhio.github.io"

cd $photo_dir

counter=1

for file in ./*; do
    echo "loading file $file"
    new_name="chubu$counter"
    counter=$((counter+1))
    
    echo "renaming file $file to $new_name.JPG"
    mv $file $new_name.JPG

    cd $prog_dir

    hugo new moments/$new_name/index.md
    cp $photo_dir/$new_name.JPG $prog_dir/content/moments/$new_name
    sed -i.bakup "s/COVER_IMG_PATH/\".\/$new_name.JPG\"/g" $prog_dir/content/moments/$new_name/index.md

    cd $photo_dir
done
