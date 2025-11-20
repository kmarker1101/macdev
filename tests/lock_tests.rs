use macdev::manifest::Lock;

#[test]
fn test_lock_new() {
    let lock = Lock::new();

    assert!(lock.packages.is_empty());
    assert!(lock.dependencies.is_empty());
    assert!(lock.impure.is_empty());
    assert_eq!(lock.metadata.macdev_version, env!("CARGO_PKG_VERSION"));
    assert!(!lock.metadata.generated.is_empty());
}

#[test]
fn test_lock_add_package() {
    let mut lock = Lock::new();

    lock.add_package(
        "python".to_string(),
        "3.11.7".to_string(),
        "python@3.11".to_string(),
    );

    assert_eq!(lock.packages.len(), 1);
    let pkg = lock.packages.get("python").unwrap();
    assert_eq!(pkg.version, "3.11.7");
    assert_eq!(pkg.formula, "python@3.11");
}

#[test]
fn test_lock_add_dependency() {
    let mut lock = Lock::new();

    lock.add_dependency(
        "python".to_string(),
        "readline".to_string(),
        "8.3.1".to_string(),
        "readline".to_string(),
    );

    assert_eq!(lock.dependencies.len(), 1);
    let dep = lock.dependencies.get("python:readline").unwrap();
    assert_eq!(dep.version, "8.3.1");
    assert_eq!(dep.formula, "readline");
}

#[test]
fn test_lock_multiple_dependencies() {
    let mut lock = Lock::new();

    lock.add_dependency(
        "python".to_string(),
        "readline".to_string(),
        "8.3.1".to_string(),
        "readline".to_string(),
    );

    lock.add_dependency(
        "python".to_string(),
        "sqlite".to_string(),
        "3.51.0".to_string(),
        "sqlite".to_string(),
    );

    assert_eq!(lock.dependencies.len(), 2);
    assert!(lock.dependencies.contains_key("python:readline"));
    assert!(lock.dependencies.contains_key("python:sqlite"));
}

#[test]
fn test_lock_serialization() {
    let mut lock = Lock::new();

    lock.add_package(
        "python".to_string(),
        "3.11.7".to_string(),
        "python@3.11".to_string(),
    );

    lock.add_dependency(
        "python".to_string(),
        "readline".to_string(),
        "8.3.1".to_string(),
        "readline".to_string(),
    );

    let toml_str = toml::to_string_pretty(&lock).unwrap();

    assert!(toml_str.contains("[metadata]"));
    assert!(toml_str.contains("[packages.python]"));
    assert!(toml_str.contains("version = \"3.11.7\""));
    assert!(toml_str.contains("formula = \"python@3.11\""));
    assert!(toml_str.contains("[dependencies.\"python:readline\"]"));
}

#[test]
fn test_lock_deserialization() {
    let toml_str = r#"
        [metadata]
        generated = "2025-11-20T18:25:24.105781+00:00"
        macdev_version = "0.1.0"

        [packages.python]
        version = "3.11.7"
        formula = "python@3.11"

        [dependencies."python:readline"]
        version = "8.3.1"
        formula = "readline"
    "#;

    let lock: Lock = toml::from_str(toml_str).unwrap();

    assert_eq!(lock.metadata.macdev_version, "0.1.0");
    assert_eq!(lock.packages.len(), 1);

    let pkg = lock.packages.get("python").unwrap();
    assert_eq!(pkg.version, "3.11.7");
    assert_eq!(pkg.formula, "python@3.11");

    assert_eq!(lock.dependencies.len(), 1);
    let dep = lock.dependencies.get("python:readline").unwrap();
    assert_eq!(dep.version, "8.3.1");
}
