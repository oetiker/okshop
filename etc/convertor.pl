perl -n -e 'chomp;(undef,$n,$m,undef,undef,undef,$u) = split /\t/;print qq{{\n    "key": ""\n    "org": "$n",\n    "motto": "$m",\n    "url": "$u"\n},\n}' data.tsv  >> okshop.cfg.dist

