# COSC352 Final Project

## Table of Contents

1. [Overview](#overview)
2. [Objective](#objective)
3. [Use](#use)

## Overview
This is my implementation of [project from a course](https://github.com/compsage/MSU_COSC352/tree/main/projects/3) taught by [Jon White]((https://www.linkedin.com/in/jon-white-bb0b174a/)), a coworker at my current job. 

## Objective

The basic objective of this project is, using an unfamiliar programming language, parse the content of a [Wikipedia Page](https://en.wikipedia.org/wiki/List_of_largest_companies_in_the_United_States_by_revenue) and extract the tables from that page to 
individual CSV files. 

Important Restrictions:
    - No external libraries. Everything must be custom or available in the language's "standard" library.
    - Containerized app with minimal user interaction necessary. The main application must run within a Docker image. Source code is expected to be mounted to a directory named `/app` in the container. 
    - Each table must be parsed and output to separate, **valid** CSV files.

Now, the students taking this course may have been assigned a language by Jon, but I had free reign to choose my language – and I chose Zig.
This was for a few reasons:
    - One of the reasons I took on this project is to gauge the difficult of the assignment and help Jon tweak it as necessary. The only thing more difficult would probs be trying to write the program in Assembly or something.
    - It's a language I've never used and hear good things about. Granted, it's always from the low-level nerds I work with, but might as well give it a try.
    - Another reason I took on this project is to talk about the process of coming to a solution – not necessarily the implementation. With a language so radically different from the regular high-level languages like Python, Java, and even C++, there's a lot more of the process that can be showcased.

I should note, I took as many shortcuts as possible focusing on getting a working app rather than a refined one. You'll see a good bit of unused code from various ideas I had while brainstorming, missing test cases, debug utilities, etc. If I ever come back around to this, I might clean it up because there's some nice general-purpose code here.

For the exact requirements, [see here.](https://github.com/compsage/MSU_COSC352/blob/main/projects/3/Readme.md) 

## Use 

Build : `docker build . --tag <tag> `

Run app: `docker run --volume $(pwd):/app <tag>` or Run Unit Tests: `docker run --volume $(pwd):/app <tag> test --summary all`

Note: Zig provides no options for managing build output so, it may look like it's just spinning for a second. Trust the process... or run add `--interactive` and `--tty` options to Docker command.

This project is not intended to be used as a template or guide, but it can definitely can be used as "inspiration." Please link back to [this repo](https://github.com/KayDVC/semmed-neo4j) or [my website](https://www.malakaispann.com) if you do.

Thanks, 

\- Kay



