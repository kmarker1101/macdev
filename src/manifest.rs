use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

const MANIFEST_FILE: &str = ".macdev/manifest.toml";
const LOCK_FILE: &str = ".macdev/manifest.lock";

fn global_manifest_path() -> Result<PathBuf> {
    let home = dirs::home_dir().context("Could not find home directory")?;
    Ok(home.join(".config/macdev/manifest.toml"))
}

#[derive(Debug, Serialize, Deserialize, Default)]
pub struct Manifest {
    #[serde(default)]
    pub packages: HashMap<String, String>,

    #[serde(default, skip_serializing_if = "HashMap::is_empty")]
    pub impure: HashMap<String, bool>,

    #[serde(default, skip_serializing_if = "HashMap::is_empty")]
    pub casks: HashMap<String, bool>,

    #[serde(default, skip_serializing_if = "HashMap::is_empty")]
    pub gc: HashMap<String, String>,

    #[serde(default, skip_serializing_if = "HashMap::is_empty")]
    pub taps: HashMap<String, bool>,
}

impl Manifest {
    /// Load manifest from current directory
    pub fn load() -> Result<Self> {
        let path = PathBuf::from(MANIFEST_FILE);
        
        if !path.exists() {
            anyhow::bail!(
                "No manifest found. Run 'macdev init' to create one."
            );
        }
        
        let contents = fs::read_to_string(&path)
            .context("Failed to read manifest")?;
        
        let manifest: Manifest = toml::from_str(&contents)
            .context("Failed to parse manifest")?;
        
        Ok(manifest)
    }

    /// Load global manifest from home directory
    pub fn load_global() -> Result<Self> {
        let path = global_manifest_path()?;

        if !path.exists() {
            return Ok(Self::default());
        }

        let contents = fs::read_to_string(&path)
            .context("Failed to read global manifest")?;

        let manifest: Manifest = toml::from_str(&contents)
            .context("Failed to parse global manifest")?;

        Ok(manifest)
    }

    /// Save as global manifest
    pub fn save_global(&self) -> Result<()> {
        let path = global_manifest_path()?;
        let dir = path.parent().context("Invalid global manifest path")?;
        fs::create_dir_all(dir)?;

        let contents = toml::to_string_pretty(self)
            .context("Failed to serialize global manifest")?;

        fs::write(&path, contents)
            .context("Failed to write global manifest")?;

        Ok(())
    }

    /// Get the global manifest path as a display string
    pub fn global_manifest_display_path() -> Result<String> {
        let path = global_manifest_path()?;
        Ok(path.display().to_string())
    }
    
    /// Save manifest to disk (local - only packages section)
    pub fn save(&self) -> Result<()> {
        let dir = Path::new(".macdev");
        fs::create_dir_all(dir)?;

        // For local manifest, only save packages section
        let local_only = Manifest {
            packages: self.packages.clone(),
            impure: HashMap::new(),
            casks: HashMap::new(),
            gc: HashMap::new(),
            taps: HashMap::new(),
        };

        let contents = toml::to_string_pretty(&local_only)
            .context("Failed to serialize manifest")?;

        fs::write(MANIFEST_FILE, contents)
            .context("Failed to write manifest")?;

        Ok(())
    }
    
    /// Add a pure package
    pub fn add_package(&mut self, name: String, version: String) {
        self.packages.insert(name, version);
    }
    
    /// Add an impure package
    pub fn add_impure(&mut self, name: String) {
        self.impure.insert(name, true);
    }

    /// Add a cask
    pub fn add_cask(&mut self, name: String) {
        self.casks.insert(name, true);
    }

    /// Remove a cask
    pub fn remove_cask(&mut self, name: &str) {
        self.casks.remove(name);
    }

    /// Add a tap
    pub fn add_tap(&mut self, name: String) {
        self.taps.insert(name, true);
    }

    /// Remove a tap
    pub fn remove_tap(&mut self, name: &str) {
        self.taps.remove(name);
    }

    /// Remove a package
    pub fn remove_package(&mut self, name: &str) {
        self.packages.remove(name);
        self.impure.remove(name);
        self.casks.remove(name);
    }
    
    /// Check if manifest exists
    pub fn exists() -> bool {
        Path::new(MANIFEST_FILE).exists()
    }
}

/// Initialize a new manifest
pub fn init() -> Result<()> {
    use colored::*;
    
    if Manifest::exists() {
        println!("{}", "Manifest already exists".yellow());
        return Ok(());
    }
    
    let manifest = Manifest::default();
    manifest.save()?;
    
    println!("{}", "✓ Initialized macdev environment".green());
    println!("  Created {}", MANIFEST_FILE.bright_black());
    
    Ok(())
}

/// List packages in manifest
pub fn list() -> Result<()> {
    use colored::*;

    // Try to load local manifest (if in a project)
    let local_manifest = Manifest::load().ok();
    let global_manifest = Manifest::load_global()?;

    let has_local = local_manifest.as_ref().map_or(false, |m| !m.packages.is_empty());
    let has_pure = !global_manifest.packages.is_empty();
    let has_impure = !global_manifest.impure.is_empty();
    let has_casks = !global_manifest.casks.is_empty();
    let has_taps = !global_manifest.taps.is_empty();

    if !has_local && !has_pure && !has_impure && !has_casks && !has_taps {
        println!("{}", "No packages, casks, or taps installed".yellow());
        return Ok(());
    }

    let global_path = Manifest::global_manifest_display_path().unwrap_or_else(|_| "global manifest".to_string());

    // Show local project packages first (if in a project)
    if let Some(local) = &local_manifest && !local.packages.is_empty() {
        println!("{}", "Project packages (from .macdev/manifest.toml):".blue().bold());
        for (name, version) in &local.packages {
            if version == "*" {
                println!("  {}", name);
            } else {
                println!("  {}@{}", name, version);
            }
        }
        println!(); // Blank line separator
    }

    if !global_manifest.taps.is_empty() {
        println!("{}", format!("Taps (from {}):", global_path).magenta().bold());
        for name in global_manifest.taps.keys() {
            println!("  {}", name);
        }
    }

    if !global_manifest.packages.is_empty() {
        if has_taps {
            println!();
        }
        println!("{}", format!("Pure packages (from {}):", global_path).green().bold());
        for (name, version) in &global_manifest.packages {
            // If the key already contains version (e.g., "python@3.12"), just show the key
            // Otherwise show key@version (e.g., "rust@*")
            if name.contains('@') {
                println!("  {}", name);
            } else {
                println!("  {}@{}", name, version);
            }
        }
    }

    if !global_manifest.impure.is_empty() {
        if has_pure || has_taps {
            println!();
        }
        println!("{}", format!("Impure packages (from {}):", global_path).cyan().bold());
        for name in global_manifest.impure.keys() {
            println!("  {}", name);
        }
    }

    if !global_manifest.casks.is_empty() {
        if has_pure || has_impure || has_taps {
            println!();
        }
        println!("{}", format!("Casks (from {}):", global_path).yellow().bold());
        for name in global_manifest.casks.keys() {
            println!("  {}", name);
        }
    }

    Ok(())
}

// Lock file structures

#[derive(Debug, Serialize, Deserialize)]
pub struct Lock {
    pub metadata: LockMetadata,
    pub packages: HashMap<String, LockedPackage>,
    #[serde(default, skip_serializing_if = "HashMap::is_empty")]
    pub dependencies: HashMap<String, LockedPackage>,
    #[serde(default, skip_serializing_if = "HashMap::is_empty")]
    pub impure: HashMap<String, LockedPackage>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LockMetadata {
    pub generated: String,
    pub macdev_version: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct LockedPackage {
    pub version: String,
    pub formula: String,
}

impl Default for Lock {
    fn default() -> Self {
        Self::new()
    }
}

impl Lock {
    /// Load lock file from current directory
    pub fn load() -> Result<Self> {
        let path = PathBuf::from(LOCK_FILE);

        if !path.exists() {
            anyhow::bail!("No lock file found");
        }

        let contents = fs::read_to_string(&path)
            .context("Failed to read lock file")?;

        let lock: Lock = toml::from_str(&contents)
            .context("Failed to parse lock file")?;

        Ok(lock)
    }

    /// Check if lock file exists
    pub fn exists() -> bool {
        Path::new(LOCK_FILE).exists()
    }

    /// Save lock file
    pub fn save(&self) -> Result<()> {
        let dir = Path::new(".macdev");
        fs::create_dir_all(dir)?;

        let contents = toml::to_string_pretty(self)
            .context("Failed to serialize lock file")?;

        fs::write(LOCK_FILE, contents)
            .context("Failed to write lock file")?;

        Ok(())
    }

    /// Create new empty lock
    pub fn new() -> Self {
        Lock {
            metadata: LockMetadata {
                generated: chrono::Utc::now().to_rfc3339(),
                macdev_version: env!("CARGO_PKG_VERSION").to_string(),
            },
            packages: HashMap::new(),
            dependencies: HashMap::new(),
            impure: HashMap::new(),
        }
    }

    /// Add a package to the lock
    pub fn add_package(&mut self, name: String, version: String, formula: String) {
        self.packages.insert(name, LockedPackage { version, formula });
    }

    /// Add a dependency to the lock
    pub fn add_dependency(&mut self, package: String, dep: String, version: String, formula: String) {
        let key = format!("{}:{}", package, dep);
        self.dependencies.insert(key, LockedPackage { version, formula });
    }
}

/// Generate lock file from current local manifest (project-specific only)
pub fn generate_lock() -> Result<()> {
    use crate::homebrew;
    use colored::*;

    // Only lock packages from LOCAL manifest (project-specific)
    // Do not lock global/impure packages (those are personal system tools)
    let local_manifest = Manifest::load()?;

    if local_manifest.packages.is_empty() {
        return Ok(());
    }

    println!("  {} Generating lock file...", "→".blue());
    let mut lock = Lock::new();

    // Lock all pure packages from this project and their dependencies
    for (name, version) in &local_manifest.packages {
        // Reconstruct package spec (e.g., "python" + "3.12" -> "python@3.12")
        let spec = if version == "*" {
            name.clone()
        } else {
            format!("{}@{}", name, version)
        };

        // Get package info
        let info = homebrew::package_info(&spec)?;
        lock.add_package(name.clone(), info.version.clone(), info.formula);
        println!("    Locked {} @ {}", name, info.version);

        // Get and lock dependencies
        let deps = homebrew::package_deps(&spec)?;
        if !deps.is_empty() {
            println!("      Locking {} dependencies...", deps.len());
            for dep in deps {
                if let Ok(dep_info) = homebrew::package_info(&dep) {
                    lock.add_dependency(
                        name.clone(),
                        dep,
                        dep_info.version,
                        dep_info.formula,
                    );
                }
            }
        }
    }

    lock.save()?;
    println!("  {} Lock file saved", "✓".green());
    Ok(())
}
