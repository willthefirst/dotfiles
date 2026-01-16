---
description: Restructure commit history for cleaner PR review
allowed-tools: Bash(git:*)
---

# Task: Clean Up Git Commit History

## Description
Restructure the commit history of the current branch to make it more readable and reviewer-friendly, while preserving the exact final state of the code. Think of it as "rewriting history" to tell a clearer story of how the changes evolved, without actually changing what the final changes are.

The current branch has changes that work (they pass CI), but the commit history may be messy - with debug commits, WIP commits, reverts, or just poorly organized changes. Transform this into a polished, logical sequence of commits that a reviewer can easily follow and understand.

## Current State

- Branch: !`git branch --show-current`
- Commits ahead of master: !`git rev-list --count master..HEAD`
- Current diff summary: !`git diff --stat master...HEAD`

## Objectives

1. **Analyze** the current changes and understand their purpose
2. **Replace** the existing commits with fresh, well-structured commits
3. **Optimize** each commit to be easy to read, understand, and follow
4. **Create** a clean, clear commit history that makes the changes abundantly clear for reviewers

## Guidelines

- Make each commit atomic and focused on a single logical change
- Use clear, descriptive commit messages
- If needed, create 'intermediate' commits to make the progression of changes easier to follow
- The goal is maximum reviewer clarity

## Critical Requirement

**IMPORTANT**: The final diff must have **NO differences** compared to the current diff, because the current diff passes CI. The end state of the code must be identical - only the commit structure should change.

Before starting, save the current HEAD sha so we can verify the final diff matches.
