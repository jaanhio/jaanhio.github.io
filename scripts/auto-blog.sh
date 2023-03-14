#!/bin/bash
# Usage: ./scripts/auto-blog.sh ./sftp-base-path /repo-base-path
set -e

current_date=$(date +'%Y-%m-%d')
sftp_path=$1
repo_path=$2

if [ -z $sftp_path ]; then
  echo "Please provide base sftp path e.g /foo/bar"
  exit 1
fi

if [ -z $repo_path ]; then
  echo "Please provide base repo path e.g /foo/bar"
  exit 1
fi

target_path=$sftp_path/$current_date

echo -e "target path: $target_path"

# find folder named after today's date
if [ ! -d $target_path ]; then
  echo "$target_path not found"
  exit 1
fi

if [ ! "$(ls -A $target_path)" ]; then
  echo "$target_path is empty"
  exit 1
fi

hugo_content_path="moments/$current_date"
full_hugo_content_path="$repo_path/content/$hugo_content_path"
index_md_path="$full_hugo_content_path/index.md"
echo "Found valid $target_path...checking if content has already been created at $index_md_path..."

if [ -f "$index_md_path" ]; then
    echo "Content already created. Exiting..."
    exit 0
fi

echo "Content not created yet...creating hugo content path: $hugo_content_path"
# else, create a new post directory using hugo new moments/{date}/index.md
(cd $repo_path && git pull origin main && hugo new $hugo_content_path/index.md)

echo "Copying files from $target_path to $full_hugo_content_path"

# loop over files. if file is of type jpeg, jpg, png, copy to post_relative_path
# cp -R $target_path/. $post_relative_path
count=0
for file in $target_path/*; do
  if [[ $file == *.jpg || $file == *.jpeg || $file == *.png ]]; then
    count=$((count+1))
    filename=$(basename $file)
    local_image_path="\".\/$filename\""
    echo "Copying $filename..."
    cp $file $full_hugo_content_path

    if [ $count -eq 1 ]; then
        echo "Setting first image $filename as cover image..."
        sed -i.bakup "s/COVER_IMG_PATH/\".\/$filename\"/g" $index_md_path #Mac's version of sed expects an extension to the -i flag e.g -i.bakup
    else
        echo "Setting image $count $filename into content..."
        echo -e "\n" >> $index_md_path
        echo "{{<image src=\"./$filename\" alt=\"moment\" position=\"center\" >}}" >> $index_md_path
    fi

    echo "Number of image processed: $count"

  else
    echo "not an image"
  fi
done

cd $repo_path
git add .
git commit -m "new moment $current_date"
git push origin main