#! /usr/bin/python3

"""Sorts a list of packages accoridng to user-defined priorities+rules.

1. read the output of debci status --all --json on stdin
2. read a bunch of priority+rules from the CLI, for instance:
     --priority '5="{package}".startswith("r")'
     --priority '40=re.search(r"kali","{version}")'
     etc
3. add a 'priority' field to each JSON document, accoding to those
   rules
4. sort the documents according to that field
5. on stdout, print the sorted list (package name only
"""


import argparse
import json
import sys

# the following could be used in rules supplied on the CL
import glob
import re


# functions
def match(status, rule):
    """Eval rule after interpolating it on status dictionary"""
    return eval(rule.format(**status))


def generate_priorities_list(cli_priorities):
    """Go from a list of <rule>=<int> (from CLI) to a somewhat easier to
       work with data structure"""
    priorities = []

    for p in cli_priorities:
        priority, rule = p.split('=', 1)
        priorities.append((int(priority),rule))

    # sort it so highest priorities come first
    return sorted(priorities, key=lambda x: x[0], reverse=True)


## main

# CLI args
parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter)
parser.add_argument('--priority-rule', action='append', default=[],
                    dest="priority_rules",
                    help="""Can be used multiple times, to pass strings of the form "<int>=<rule>".

<int> will be the priority (highest priorities are queued first)
assigned to all packages that match the associated <rule>.

Examples:
  --priority '5="{package}".startswith("r")': priority 5 for packages starting with 'r'
  --priority '40=re.search(r"kali","{version}")': priority 40 for packages whose version contains 'kali'
""")
args = parser.parse_args(sys.argv[1:])

# read JSON status (debci status --json --all) from stdin
statuses = json.loads(sys.stdin.read())

# get priorities
priorities = generate_priorities_list(args.priority_rules)

# assign a priority to each package
for status in statuses:
    status['priority'] = 0 # start with a low default
    for priority, rule in priorities:
        if match(status, rule):
            status['priority'] = priority
            # stop processinglowest matching priority wins
            break

# sort according to this new 'priority' field
sorted_statuses = sorted(statuses,
                         key = lambda status: status['priority'],
                         reverse = True)

# print the result
for status in sorted_statuses:
    print(status['package'])
