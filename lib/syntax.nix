{ lib }: with lib; let
  attrNeedsQuote = s: any (flip hasInfix s) [ "." ''"'' ];
  quoteString = s: ''"${replaceStrings [ ''"'' ] [ ''\"'' ] s}"'';
  attrString = path: concatStringsSep "." path;
  attrName = component: if attrNeedsQuote component
    then quoteString component
    else component;
  unqualified = name: {
    # an attr refering to implicit scope
    type = "syntax_unqualified";
    inherit name;
    __toString = self: self.name;
  };
  attrPath = target: path: {
    # qualified attr path that refers to some other object
    type = "syntax_qualified";
    inherit target path;
    #__toString = self: ?;
  };
  apply = target: arg: {
    type = "syntax_apply";
    inherit target arg;
  };
  # TODO: fn: wrap a function and store its args for later serialization, but also call it
  # TODO: eval that evaluates all these .type things
  eval = value:
    if value.type or null == "syntax_unqualified" then throw "TODO eval:syntax_unqualified"
    else if value.type or null == "syntax_qualified" then flip attrByPath (eval value.target) value.path
    else if value.type or null == "syntax_apply" then (eval value.target) (eval value.arg)
    else value;
  surround = expr: "(" + expr + ")";
  maybeSurround = surround': expr:
    if surround' then surround expr
    else expr;
  surroundExpr = value: exprValue { inherit value; surround = true; };
  expr = value: exprValue { inherit value; };
  exprValue = { surround ? false, value }:
    if isString value then quoteString value
    else if isDerivation value then exprValue {
      inherit surround;
      value = apply (unqualified "import") (/. + (builtins.unsafeDiscardStringContext value.drvPath));
    } else if value.type or null == "syntax_unqualified" then value.name
    else if value.type or null == "syntax_qualified" then surroundExpr value.target
      + optionalString (value.path != [ ]) "." + concatMapStringsSep "." attrName value.path
    else if value.type or null == "syntax_apply" then maybeSurround surround (
      concatMapStringsSep " " surroundExpr [ value.target value.arg ]
    ) else if isList value then concatStringsSep " " (
      singleton "["
      ++ map surroundExpr value
      ++ singleton "]"
    ) else if isAttrs value then "{ " + concatStrings (
      mapAttrsToList (k: v:
        ''${attrName k} = ${expr v}; ''
      ) value
    ) + "}"
    else if value == true then "true"
    else if value == false then "false"
    else if value == null then "null"
    else toString value;
  attrExpr = { file, attr, args }: let
    imported = apply (unqualified "import") file;
    applied = if args != null
      then apply imported args
      else imported;
    pathed = if attr != [ ]
      then attrPath applied attr
      else applied;
  in expr pathed;
  optionStr = value:
    if value == true then "true"
    else if value == false then "false"
    else toString value;
  cliArgs = { nixVersion ? builtins.nixVersion, file, attr, args ? { }, options ? { } }: let
    needsExpr = any attrNeedsQuote path;
    exprStr = attrExpr { inherit file attr args; };
    fileStr = toString file;
    attrStr = attrString attr;
    expr1 = if needsExpr
      then [ "-E" exprStr ]
      else [ fileStr "-A" attrStr ];
    expr2 = if needsExpr
      then singleton (surround exprStr)
      else [ "-f" fileStr attrStr ];
    expr2_4 = if needsExpr
      then [ "--expr" exprStr ]
      else [ "-f" fileStr attrStr ];
    expr = if versionAtLeast nixVersion "2.4" then expr2_4
      else if versionAtLeast nixVersion "2.0" then expr2 # TODO: and experimental-features?
      else expr1;
    optionlist = mapAttrsToList (k: v: [ "--option" k (optionStr v) ]) options;
    arglist = mapAttrsToList (k: v: if isString v
      then [ "--argstr" k v ]
      else [ "--arg" k (expr v) ]
    ) args;
  in concatLists optionlist ++ optionals (!needsExpr) arglist ++ expr;
  argValuePrimitives = with types; [ (nullOr str) path int float bool ];
  argValueTypes = with types; argValuePrimitives ++ [ (listOf argValueType) (attrsOf argValueType) ];
  argValueType = types.oneOf argValueTypes;
  optionValueType = with types; nullOr (oneOf [ str int bool ]);
  attrPathType = let
    conv = splitString ".";
  in with types; coercedTo str conv (listOf str);
in {
  inherit eval expr surroundExpr exprValue
    apply unqualified attrPath
    attrName attrNeedsQuote quoteString
    argValueType optionValueType attrPathType
    cliArgs;
}
