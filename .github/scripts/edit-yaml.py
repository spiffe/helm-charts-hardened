#!/usr/bin/env python3

import os
import sys
from dict_deep import deep_set
import ruamel.yaml

def represent_none(self, data):
    return self.represent_scalar(u'tag:yaml.org,2002:null', u'null')

y = ruamel.yaml.YAML()
y.indent(mapping=2, sequence=4, offset=2)
# Dont wrap long lines
y.width = 4096
y.preserve_quotes = True
y.representer.add_representer(type(None), represent_none)

d = y.load(open(os.environ['VALUES']))

tagquery = os.environ['QUERY'] + '.tag'

deep_set(d, tagquery, os.environ['LATEST_VERSION']);

y.dump(d, sys.stdout)
