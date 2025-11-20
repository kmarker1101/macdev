use macdev::manifest::Manifest;

#[test]
fn test_manifest_default() {
    let manifest = Manifest::default();
    assert!(manifest.packages.is_empty());
    assert!(manifest.impure.is_empty());
    assert!(manifest.gc.is_empty());
    assert!(manifest.taps.is_empty());
}

#[test]
fn test_manifest_add_package() {
    let mut manifest = Manifest::default();
    manifest.add_package("python".to_string(), "3.11".to_string());

    assert_eq!(manifest.packages.len(), 1);
    assert_eq!(manifest.packages.get("python"), Some(&"3.11".to_string()));
}

#[test]
fn test_manifest_add_impure() {
    let mut manifest = Manifest::default();
    manifest.add_impure("git".to_string());

    assert_eq!(manifest.impure.len(), 1);
    assert_eq!(manifest.impure.get("git"), Some(&true));
}

#[test]
fn test_manifest_add_tap() {
    let mut manifest = Manifest::default();
    manifest.add_tap("homebrew/cask".to_string());

    assert_eq!(manifest.taps.len(), 1);
    assert_eq!(manifest.taps.get("homebrew/cask"), Some(&true));
}

#[test]
fn test_manifest_remove_package() {
    let mut manifest = Manifest::default();
    manifest.add_package("python".to_string(), "3.11".to_string());
    manifest.add_impure("python".to_string());

    manifest.remove_package("python");

    assert!(manifest.packages.is_empty());
    assert!(manifest.impure.is_empty());
}

#[test]
fn test_manifest_remove_tap() {
    let mut manifest = Manifest::default();
    manifest.add_tap("homebrew/cask".to_string());

    manifest.remove_tap("homebrew/cask");

    assert!(manifest.taps.is_empty());
}

#[test]
fn test_manifest_serialization() {
    let mut manifest = Manifest::default();
    manifest.add_package("python".to_string(), "3.11".to_string());
    manifest.add_package("rust".to_string(), "*".to_string());

    let toml_str = toml::to_string(&manifest).unwrap();

    assert!(toml_str.contains("[packages]"));
    assert!(toml_str.contains("python = \"3.11\""));
    assert!(toml_str.contains("rust = \"*\""));
}

#[test]
fn test_manifest_deserialization() {
    let toml_str = r#"
        [packages]
        python = "3.11"
        rust = "*"

        [impure]
        git = true
    "#;

    let manifest: Manifest = toml::from_str(toml_str).unwrap();

    assert_eq!(manifest.packages.len(), 2);
    assert_eq!(manifest.packages.get("python"), Some(&"3.11".to_string()));
    assert_eq!(manifest.packages.get("rust"), Some(&"*".to_string()));
    assert_eq!(manifest.impure.len(), 1);
    assert_eq!(manifest.impure.get("git"), Some(&true));
}
