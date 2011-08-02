#!/bin/bash

# get and manage the paizo login and cookies, et al.

case "$#" in
  1 ) email="plambert@plambert.net"; pass="$1"; shift ;;
  2 ) email="$1"; shift; pass="$1"; shift ;;
  * ) echo "usage: $0 [email] <password>"; exit 0 ;;
esac

for cookie_jar in "${HOME}/.curl_cookies" "${HOME}/.paizo_cookies" "./cookiejar"; do
  [[ -f "${cookie_jar}" ]] && break
done

echo "cookie jar = ${cookie_jar}"

tmpfile="$(mktemp -t paizo)"

trap 'rm -f "${tmpfile}" >/dev/null 2>&1' EXIT

pcurl () { 
  curl --compressed -L -A "$agent" -b "$cookie_jar" -c "$cookie_jar" "$@"
}

# get initial cookies

pcurl -s -o "${tmpfile}" 'https://secure.paizo.com/cgi-bin/WebObjects/Store.woa/wa/DirectAction/signIn?path=paizo%2Faccount%2Fassets'

# get 'path' form value

get_form_path() {
  grep '<input.*name="path"' "$1" \
  | head -1 \
  | sed -e 's/.*value="//' -e 's/".*//' 
}

#form_path="$( get_form_path "${tmpfile}" )"
form_path="paizo/account/assets"

echo "form path = ${form_path}"

pcurl -o "${tmpfile}" -s -d "path=${form_path}&e=${email}&p=${pass}&WOSubmitAction=signIn" 'https://secure.paizo.com/cgi-bin/WebObjects/Store.woa/wa/signIn'

#            <tr>
#              <td colspan = "5">
#                <br />
#                <br />
#                <b>0one Games</b>
#                <br />
#                <hr />
#              </td>
#            </tr>
#            
#  <tr bgcolor="#eeeeee">
#    <td nowrap width = "18"></td>
#    <td>
#      <a href="/cgi-bin/WebObjects/Store.woa/wo/16.2.1.StandardPageTemplate.35.3.1.1.2.3.5.1.1.MAAssets.2.7.1.13.1.0.3.0.1.1">
#        <b> 0one's Black & White: Heavenring Village—Virtual Boxed Set PDF </b>
#      </a>
#      
#      
#      
#    </td>
#    <td width = "120" class = "tiny" align = "center">
#      
#      no data
#    </td>
#    <td width = "120" class = "tiny" align = "center">May 2010</td>
#    <td width = "120" class = "tiny" align = "center">July 2010</td>
#  </tr>

perl -e '
  while(defined($line=<>)){
    chomp $line;
    if ($line =~ /^\s*<td colspan = "5">\s*$/) {
      while(defined($line=<>)) {
        chomp $line;
        if ($line =~ /^\s*<b>(.*)<\/b>\s*$/) {
          $publisher=$1;
          printf "=== %s\n", $publisher;
        }
        elsif ($line =~ /^\s*<\/tr>\s*$/) {
          last;
        }
      }
    }
    elsif ($line =~ m{^\s*<a href="(/cgi-bin/WebObjects/Store.woa/wo/[^"]+)">\s*$}) {
      $url=$1;
      $downloaded=undef; $updated=undef; $added=undef;
      $line=<>; chomp $line;
      $line =~ m{<b> (.*) </b>};
      $name=$1;
      printf "%s\n  %s\n", $name, $url;
      while(defined($line=<>)) {
        chomp $line;
        last if ($line =~ m{^\s*</tr>\s*$});
        if ($line =~ m{^\s*<td [^>]+>\s*$}) {
          $line=<>; chomp $line;
          if ($line =~ m{^\s*(\S.*)\s*$}) {
            $downloaded=$1;
          }
        }
        elsif ($line =~ m{^\s*<td [^>]+>(.*?)</td>}) {
          if ($updated) {
            $added=$1;
          }
          else {
            $updated=$1;
          }
        }
      }
      printf "  downloaded=%s updated=%s added=%s\n", $downloaded || "-", $updated || "-", $added || "-";
    }
  }
' "${tmpfile}"

