use macdev::environment::parse_package_spec;

#[test]
fn test_parse_versioned_package() {
    let (package, version) = parse_package_spec("python@3.11");
    assert_eq!(package, "python@3.11");
    assert_eq!(version, Some("3.11".to_string()));
}

#[test]
fn test_parse_unversioned_package() {
    let (package, version) = parse_package_spec("rust");
    assert_eq!(package, "rust");
    assert_eq!(version, None);
}

#[test]
fn test_parse_multiple_at_signs() {
    // Should use rightmost @ for version
    let (package, version) = parse_package_spec("node@lts@20");
    assert_eq!(package, "node@lts@20");
    assert_eq!(version, Some("20".to_string()));
}

#[test]
fn test_parse_empty_version() {
    let (package, version) = parse_package_spec("package@");
    assert_eq!(package, "package@");
    assert_eq!(version, Some("".to_string()));
}
