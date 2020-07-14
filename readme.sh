#!/bin/bash

readonly GITHUB_TOKEN=${GITHUB_TOKEN}

readonly pushes_query="
{
  user(login: \"mshick\") {
    repositories(first: 10, privacy: PUBLIC, orderBy: {field: PUSHED_AT, direction: DESC}, ownerAffiliations: [OWNER]) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        name
        description
        url
        pushedAt
      }
    }
  }
}
"

function github_query {
  local token="$1"
  local formatted_query="${2//[$'\t\r\n']}"

  curl -sS \
    --request 'POST' \
    --url 'https://api.github.com/graphql' \
    --header "authorization: Bearer ${token}" \
    --header "content-type: application/json" \
    --data "{\"query\":\"${formatted_query}\"}"
}

function insert_between {
  awk -i inplace \
    -v begin="$1" \
    -v end="$2" \
    -v data="$3" '$0~end{f=0} !f{print} $0~begin{print data,new; f=1}' \
    "$4"
}

function format_pushes_text {
  local TZ='America/New_York'  
  local IFS=','
  
  declare -a data=( )

  while read -ra data; do
    local name=${data[0]}
    name="${name%\"}"
    name="${name#\"}"

    local url=${data[1]}
    url="${url%\"}"
    url="${url#\"}"

    local pushed_at=${data[2]}
    pushed_at="${pushed_at%\"}"
    pushed_at="${pushed_at#\"}"    
    pushed_at=$(gnudate --date "${pushed_at}" --iso-8601=minutes)    

    echo "- <samp>[${name}](${url}) <kbd>${pushed_at}</kbd></samp>"
  done  
}

function posts_request {
  curl -sS \
    --request 'GET' \
    --url 'https://github.blog/feed/'
}

function gnudate {
    if hash gdate 2>/dev/null; then
        gdate "$@"
    else
        date "$@"
    fi
}

function process_atom_feed {
  local TZ='America/New_York'
  local IFS='>'
  local tag=''
  local value=''

  while read -d '<' tag value; do
    case ${tag/%\ */} in
      'entry')
        title=''
        link=''
        pubDate=''
        description=''
        datetime=''
        ;;
      'title')
        title="$value"
        ;;
      'link')
        link=$(echo $tag | sed -e 's/.*href="\([^"]*\).*/\1/')
        ;;
      'updated')
        datetime=$(gnudate --date "$value" --iso-8601=minutes)
        pubDate=$(gnudate --date "$value" '+%D %H:%M%P')
        ;;
      '/entry')
        echo "- <samp>[${title}](${link}) <kbd>${datetime}</kbd></samp>"
        ;;
    esac
  done
}

function process_rss_feed {
  local TZ='America/New_York'
  local IFS='>'
  local tag=''
  local value=''

  while read -d '<' tag value; do
    case ${tag/%\ */} in
      'item')
        title=''
        link=''
        pubDate=''
        description=''
        datetime=''
        ;;
      'title')
        title="$value"
        ;;
      'link')
        link="$value"
        ;;
      'pubDate')
        datetime=$(gnudate --date "$value" --iso-8601=minutes)
        pubDate=$(gnudate --date "$value" '+%D %H:%M%P')
        ;;
      '/item')
        echo "- <samp>[${title}](${link}) <kbd>${datetime}</kbd></samp>"
        ;;
    esac
  done
}

function main {
  local pushes_response=$(github_query "$GITHUB_TOKEN" "$pushes_query")
  local pushes=$(echo "$pushes_response" | jq -r '.data.viewer.repositories.nodes[] | [.name, .url, .pushedAt] | @csv' | format_pushes_text)
  insert_between \
    "<!-- PUSHES:START -->" \
    "<!-- PUSHES:END -->" \
    "\n$pushes\n" \
    README.md

  local posts_response=$(posts_request)
  local posts=$(echo "$posts_response" | process_rss_feed)
  insert_between \
    "<!-- POSTS:START -->" \
    "<!-- POSTS:END -->" \
    "\n$posts\n" \
    README.md
}

main "$@"