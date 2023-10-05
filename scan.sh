#!/bin/bash
for p in $1*
do
  for v in $(yq -r '.versions | keys[]' $p/config.yml)
  do
    recipe_path=$(yq -r .versions.\"$v\".folder $p/config.yml)
    has_shared=$(conan inspect --format=json $p/$recipe_path | yq '.options | has("shared")')
    filter="os=Linux"
    if [[ $has_shared == true ]]
    then
      filter+=" and options.shared=True"
    fi
    conan download "$p/$v:*" -r conancenter -p "$filter" --format=json >pkglist.json
    for r in $(yq -r '."Local Cache" | keys[] as $pv | .[$pv].revisions | keys[] as $r | .[$r].packages | keys[] as $p | "\($pv)#\($r):\($p)"' pkglist.json)
    do
      for f in $(conan cache path $r)/lib/*.so*
      do
        if [[ -f $f && ! -L $f ]]
        then
          for symbol in $(readelf -Ws $f |  awk '{ if ($7 == "UND") { print $8} }')
          do
            symbol=$(echo $symbol | cut -d '@' -f 1)
            if [[ "$symbol" =~ (?x)^([a-zA-Z0-9_]*__[a-zA-Z0-9_]+_finite|
              _dn_comp|
              __dn_expand|
              __dn_skipname|
              __res_dnok|
              __res_hnok|
              __res_mailok|
              __res_mkquery|
              __res_nmkquery|
              __res_nquery|
              __res_nquerydomain|
              __res_nsearch|
              __res_nsend|
              __res_ownok|
              __res_query|
              __res_querydomain|
              __res_search|
              __res_send|
              __xmknod|
              __xmknodat)$ ]]
            then
              echo "::error ::$p/$v $symbol in $f not present in new libc versions"
            fi
          done
        fi
      done
      conan remove -c $r >/dev/null
    done
    conan remove -c "$p/$v" >/dev/null
  done
done