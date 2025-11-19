use anyhow::{Context, Result};
use colored::*;
use std::fs;
use std::os::unix::fs as unix_fs;
use std::path::{Path, PathBuf};

use crate::homebrew;
use crate::manifest::Manifest;

const PROFILE_DIR: &str = ".macdev/profile";

/// Parse package spec (e.g., "python@3.11" -> ("python@3.11", "3.11"))
fn parse_package_spec(spec: &str) -> (String, Option<String>) {
    if let Some(pos) = spec.rfind('@') {
        let name = spec[..pos].to_string();
        let version = spec[pos + 1..].to_string();
        (format!("{}@{}", name, version), Some(version))
    } else {
        (spec.to_string(), None)
    }
}

/// Add a package to the environment
pub fn add(package_spec: &str, impure: bool) -> Result<()> {
    // Check Homebrew is installed
    if !homebrew::is_installed() {
        anyhow::bail!("Homebrew is not installed. Install it from https://brew.sh");
    }

    // For pure packages, check that manifest exists BEFORE installing anything
    if !impure && !Manifest::exists() {
        anyhow::bail!("No manifest found. Run 'macdev init' first to initialize the environment.");
    }

    let (package, version) = parse_package_spec(package_spec);

    let mut global_manifest = Manifest::load_global()?;
    let name = package.split('@').next().unwrap().to_string();

    // Check if package is in gc section and remove it
    let was_in_gc = global_manifest.gc.remove(&name).is_some();
    if was_in_gc {
        println!("  Package was in gc, restoring...");
    }

    if impure {
        // Impure: install normally (with linking) and track in global manifest
        println!("{} {} (impure)", "Adding".green(), package);
        homebrew::ensure_package(&package, true)?; // link=true

        global_manifest.add_impure(name);
        global_manifest.save_global()?;

        let path = Manifest::global_manifest_display_path()?;
        println!("{} Package available system-wide (saved to {})", "✓".green(), path);
    } else {
        // Pure: install with --no-link and track in both local and global manifests
        println!("{} {} (pure)", "Adding".green(), package);
        let brew_path = homebrew::ensure_package(&package, false)?; // link=false

        // Create symlinks
        create_symlinks(&package, &brew_path)?;

        let ver = version.unwrap_or_else(|| "*".to_string());

        // Track in local manifest (this project needs it)
        let mut local_manifest = Manifest::load()?;
        local_manifest.add_package(name.clone(), ver.clone());
        local_manifest.save()?;

        // Track in global manifest (it's installed in Homebrew)
        global_manifest.add_package(name, ver);
        global_manifest.save_global()?;

        println!("{} Package isolated to this project", "✓".green());
    }

    // Unlink dependencies that aren't in the manifest (applies to both pure and impure)
    let deps = homebrew::package_deps(&package)?;
    if !deps.is_empty() {
        println!("  Checking dependencies...");
        for dep in deps {
            // Check if dependency is in manifest (pure or impure)
            if !global_manifest.packages.contains_key(&dep) &&
               !global_manifest.impure.contains_key(&dep) &&
               !global_manifest.gc.contains_key(&dep) {
                println!("    Unlinking {} (dependency)", dep);
                let _ = homebrew::unlink_package(&dep); // Ignore errors
            }
        }
    }

    Ok(())
}

/// Remove a package from the environment
pub fn remove(package: &str) -> Result<()> {
    use colored::*;

    // Try to load local manifest (ok if it doesn't exist - not in a project)
    let local_manifest = Manifest::load().ok();
    let mut global_manifest = Manifest::load_global()?;

    // Check if package exists in global manifest
    let is_global_pure = global_manifest.packages.contains_key(package);
    let is_global_impure = global_manifest.impure.contains_key(package);

    if !is_global_pure && !is_global_impure {
        anyhow::bail!("Package '{}' is not tracked globally", package);
    }

    println!("{} {} from environment", "Removing".yellow(), package);

    if is_global_impure {
        // Impure package: move to gc section in global manifest
        global_manifest.impure.remove(package);
        global_manifest.gc.insert(package.to_string(), "*".to_string());
        global_manifest.save_global()?;
        println!("{} Removed {} (impure, moved to gc)", "✓".green(), package);
    } else {
        // Pure package: remove from local if in a project, move to gc in global
        if let Some(mut local) = local_manifest && local.packages.contains_key(package) {
            local.remove_package(package);
            local.save()?;

            // Rebuild profile (removes symlinks for pure packages)
            rebuild_profile(&local)?;
            println!("  Removed from local project manifest");
        }

        // Move from packages to gc in global manifest
        if let Some(version) = global_manifest.packages.remove(package) {
            global_manifest.gc.insert(package.to_string(), version);
        }
        global_manifest.save_global()?;

        println!("{} Removed {} (moved to gc)", "✓".green(), package);
    }

    Ok(())
}

/// Sync packages from manifest(s)
pub fn sync() -> Result<()> {
    use colored::*;

    let local_manifest = Manifest::load().ok();
    let global_manifest = Manifest::load_global()?;

    println!("{}", "Syncing packages from manifest(s)...".cyan().bold());
    println!();

    let mut synced_count = 0;

    // If in a project, sync pure packages from local manifest
    if let Some(local) = &local_manifest && !local.packages.is_empty() {
        println!("{}", "Syncing pure packages from local manifest:".green());

        for (name, version) in &local.packages {
            // Check if package is in global manifest (not in gc)
            if !global_manifest.packages.contains_key(name) {
                let spec = if version == "*" {
                    name.clone()
                } else {
                    format!("{}@{}", name, version)
                };

                println!("  {} {}", "→".blue(), spec);
                add(&spec, false)?;
                synced_count += 1;
            } else {
                println!("  {} {} (already installed)", "✓".green(), name);
            }
        }
        println!();
    }

    // Sync impure packages from global manifest
    if !global_manifest.impure.is_empty() {
        println!("{}", "Syncing impure packages from global manifest:".cyan());

        for name in global_manifest.impure.keys() {
            // Check if package is actually installed in Homebrew
            match homebrew::is_package_installed(name) {
                Ok(true) => {
                    println!("  {} {} (already installed)", "✓".green(), name);
                }
                Ok(false) | Err(_) => {
                    println!("  {} {}", "→".blue(), name);
                    add(name, true)?;
                    synced_count += 1;
                }
            }
        }
    }

    println!();
    if synced_count > 0 {
        println!("{} Synced {} package(s)", "✓".green(), synced_count);
    } else {
        println!("{}", "All packages already synced".yellow());
    }

    Ok(())
}

/// Garbage collect packages marked for removal
pub fn gc() -> Result<()> {
    use colored::*;

    let mut global_manifest = Manifest::load_global()?;

    if global_manifest.gc.is_empty() {
        println!("{}", "No packages to garbage collect".yellow());
        return Ok(());
    }

    println!("{}", "Garbage collecting unused packages...".cyan().bold());
    println!();

    let mut to_remove = Vec::new();

    for name in global_manifest.gc.keys() {
        println!("  {} {}", "Uninstalling".red(), name);

        match homebrew::uninstall_package(name) {
            Ok(_) => {
                to_remove.push(name.clone());
            }
            Err(e) => {
                println!("    {} Failed to uninstall: {}", "⚠".yellow(), e);
                println!("    Keeping in gc for next run");
            }
        }
    }

    // Remove successfully uninstalled packages from gc
    for name in &to_remove {
        global_manifest.gc.remove(name);
    }

    global_manifest.save_global()?;

    println!();
    if !to_remove.is_empty() {
        println!("{} Uninstalled {} package(s)", "✓".green(), to_remove.len());
    }

    // Run brew cleanup
    println!();
    println!("{}", "Running brew cleanup...".cyan());
    homebrew::cleanup()?;

    println!("{}", "✓ Garbage collection complete".green());

    Ok(())
}

/// Install all packages from manifest
pub fn install() -> Result<()> {
    use colored::*;

    let local_manifest = Manifest::load()?;
    let mut global_manifest = Manifest::load_global()?;

    println!("{}", "Installing packages from manifest...".cyan().bold());

    // Install pure packages from local manifest (no link)
    for (name, version) in &local_manifest.packages {
        let spec = if version == "*" {
            name.clone()
        } else {
            format!("{}@{}", name, version)
        };

        println!("  {} {}", "→".blue(), spec);
        let brew_path = homebrew::ensure_package(&spec, false)?; // link=false
        create_symlinks(&spec, &brew_path)?;

        // Track in global manifest (it's now installed in Homebrew)
        global_manifest.add_package(name.clone(), version.clone());
    }

    // Save global manifest with newly installed pure packages
    if !local_manifest.packages.is_empty() {
        global_manifest.save_global()?;
    }

    println!("{} All packages installed", "✓".green());

    Ok(())
}

/// Create symlinks for a package
fn create_symlinks(_package: &str, brew_path: &Path) -> Result<()> {
    let profile_dir = PathBuf::from(PROFILE_DIR);
    fs::create_dir_all(&profile_dir)?;

    // Link bin directory
    let brew_bin = brew_path.join("bin");
    if brew_bin.exists() {
        link_directory(&brew_bin, &profile_dir.join("bin"))?;
    }

    // ALSO link libexec/bin if it exists (this is where unversioned symlinks live)
    let libexec_bin = brew_path.join("libexec/bin");
    if libexec_bin.exists() {
        link_directory(&libexec_bin, &profile_dir.join("bin"))?;
    }

    // Link lib directory
    let brew_lib = brew_path.join("lib");
    if brew_lib.exists() {
        link_directory(&brew_lib, &profile_dir.join("lib"))?;
    }

    Ok(())
}

/// Link all files from source directory to target directory
fn link_directory(source: &Path, target: &Path) -> Result<()> {
    fs::create_dir_all(target)?;

    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let name = entry.file_name();
        let target_path = target.join(&name);

        // Remove existing symlink if present
        if target_path.exists() || target_path.symlink_metadata().is_ok() {
            let _ = fs::remove_file(&target_path);
        }

        unix_fs::symlink(entry.path(), target_path)?;
    }

    Ok(())
}

/// Rebuild the profile directory from scratch
fn rebuild_profile(manifest: &Manifest) -> Result<()> {
    let profile_dir = PathBuf::from(PROFILE_DIR);

    // Delete entire profile directory
    if profile_dir.exists() {
        fs::remove_dir_all(&profile_dir)
            .context("Failed to remove profile directory")?;
    }

    // Recreate symlinks for all remaining pure packages
    if !manifest.packages.is_empty() {
        println!("  Rebuilding environment...");

        for (name, version) in &manifest.packages {
            let spec = if version == "*" {
                name.clone()
            } else {
                format!("{}@{}", name, version)
            };

            let brew_path = homebrew::package_prefix(&spec)?;
            create_symlinks(&spec, &brew_path)?;
        }
    }

    Ok(())
}
