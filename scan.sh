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
      offending_libs=""
      for f in $(conan cache path $r)/lib/*.so*
      do
        if [[ -f $f && ! -L $f ]]
        then
          missing_symbols=""
          for symbol in $(readelf -Ws $f |  awk '{ if ($7 == "UND") { print $8} }')
          do
            symbol=$(echo $symbol | cut -d '@' -f 1)
            pattern="[a-zA-Z0-9_]*__[a-zA-Z0-9_]+_finite"
            pattern+="|_dn_comp"
            pattern+="|__dn_expand"
            pattern+="|__dn_skipname"
            pattern+="|__res_dnok"
            pattern+="|__res_hnok"
            pattern+="|__res_mailok"
            pattern+="|__res_mkquery"
            pattern+="|__res_nmkquery"
            pattern+="|__res_nquery"
            pattern+="|__res_nquerydomain"
            pattern+="|__res_nsearch"
            pattern+="|__res_nsend"
            pattern+="|__res_ownok"
            pattern+="|__res_query"
            pattern+="|__res_querydomain"
            pattern+="|__res_search"
            pattern+="|__res_send"
            pattern+="|__xmknod"
            pattern+="|__xmknodat"
            if [[ "$symbol" =~ ^($pattern)$ ]]
            then
              missing_symbols+="$symbol,"
            fi
          done
          if [[ ! -z "$missing_symbols" ]]
          then
            offending_libs+="$f(${missing_symbols::-1}), "
          fi
        fi
      done
      if [[ ! -z "$offending_libs" ]]
      then
        echo "::error ::$p/$v symbols not present in new libc versions: ${offending_libs::-2}"
      fi
      conan remove -c $r >/dev/null
    done
    conan remove -c "$p/$v" >/dev/null
  done
done
