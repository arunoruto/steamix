# Compares linux-armada's final config with Armada's fragment. nixpkgs'
# common config is answered after the fragment, so it can override it; this
# fails if anything Armada builds in ended up a module or off, and lists
# every other difference. Only generates the config, so it is cheap, also
# cross-compiled from x86_64.
{
  runCommand,
  kernel,
  armada,
}:
runCommand "linux-armada-config-test" { } ''
  fragment=${armada}/config/armada-kernel.config.overrides
  config=${kernel.configfile}
  failed=0

  while IFS= read -r line; do
    case "$line" in
      CONFIG_*=*)
        want=''${line%%#*}
        want=$(echo "$want" | sed -E 's/[[:space:]]+$//')
        symbol=''${want%%=*}
        value=''${want#*=}
        ;;
      "# CONFIG_"*" is not set")
        symbol=''${line#\# }
        symbol=''${symbol%% *}
        value=n
        ;;
      *) continue ;;
    esac

    actual=$(sed -n "s/^$symbol=//p" "$config")
    [ -n "$actual" ] || actual=n
    [ "$actual" = "$value" ] && continue

    if [ "$value" = y ]; then
      echo "FAIL  $symbol: Armada builds it in, the config has $actual"
      failed=1
    else
      echo "note  $symbol: Armada has $value, the config has $actual"
    fi
  done < "$fragment"

  [ "$failed" = 0 ] || exit 1
  echo ok > "$out"
''
