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
            // Extract base name (e.g., "python@3.14" -> "python")
            let dep_base = dep.split('@').next().unwrap();

            // Check if dependency (or its base name) is in manifest (pure or impure)
            let in_packages = global_manifest.packages.contains_key(&dep) ||
                             global_manifest.packages.contains_key(dep_base);
            let in_impure = global_manifest.impure.contains_key(&dep) ||
                           global_manifest.impure.contains_key(dep_base);
            let in_gc = global_manifest.gc.contains_key(&dep) ||
                       global_manifest.gc.contains_key(dep_base);

            if !in_packages && !in_impure && !in_gc {
                println!("    Unlinking {} (dependency)", dep);
                let _ = homebrew::unlink_package(&dep); // Ignore errors
            }
        }
    }

    // Generate lock file
    let _ = crate::manifest::generate_lock(); // Ignore errors

    Ok(())
}

/// Remove a package from the environment
pub fn remove(package: &str) -> Result<()> {
    use colored::*;

    // Extract base name (e.g., "python@3.12" -> "python")
    let package_base = package.split('@').next().unwrap();

    // Try to load local manifest (ok if it doesn't exist - not in a project)
    let local_manifest = Manifest::load().ok();
    let mut global_manifest = Manifest::load_global()?;

    // Determine which section the package is in (prioritize specific matches)
    let has_version = package.contains('@');

    // Check for exact matches first
    let exact_pure = global_manifest.packages.contains_key(package);
    let exact_impure = global_manifest.impure.contains_key(package);

    // Check for base name matches
    let base_pure = global_manifest.packages.contains_key(package_base);
    let base_impure = global_manifest.impure.contains_key(package_base);

    // Decide which section to remove from:
    // 1. If versioned (e.g., node@22), prefer pure packages
    // 2. If exact match exists, use that section
    // 3. Otherwise use base match
    let is_impure = if has_version {
        // For versioned packages, only remove from impure if exact match or no pure match
        exact_impure || (!exact_pure && !base_pure && base_impure)
    } else {
        // For unversioned, prefer exact match, then base match
        exact_impure || (!exact_pure && base_impure)
    };

    if !exact_pure && !exact_impure && !base_pure && !base_impure {
        anyhow::bail!("Package '{}' is not tracked globally", package);
    }

    println!("{} {} from environment", "Removing".yellow(), package);

    if is_impure {
        // Impure package: move to gc section in global manifest
        // Try both full name and base name
        let removed = global_manifest.impure.remove(package).is_some() ||
                     global_manifest.impure.remove(package_base).is_some();
        if removed {
            // For impure packages, use the original package name (may include version)
            let gc_key = if package.contains('@') {
                package.to_string()
            } else {
                package_base.to_string()
            };
            global_manifest.gc.insert(gc_key, "*".to_string());
            global_manifest.save_global()?;
            println!("{} Removed {} (impure, moved to gc)", "✓".green(), package);
        }
    } else {
        // Pure package: remove from local if in a project, move to gc in global
        let pkg_key = if local_manifest.as_ref().is_some_and(|m| m.packages.contains_key(package)) {
            package
        } else {
            package_base
        };

        if let Some(mut local) = local_manifest && local.packages.contains_key(pkg_key) {
            local.remove_package(pkg_key);
            local.save()?;

            // Rebuild profile (removes symlinks for pure packages)
            rebuild_profile(&local)?;
            println!("  Removed from local project manifest");
        }

        // Move from packages to gc in global manifest
        // Try both full name and base name
        let version = global_manifest.packages.remove(package)
                        .or_else(|| global_manifest.packages.remove(package_base));
        if let Some(ver) = version {
            // Store full package spec (name@version) in gc, not just base name
            let gc_key = if ver == "*" {
                package_base.to_string()
            } else {
                format!("{}@{}", package_base, ver)
            };
            global_manifest.gc.insert(gc_key, ver);
        }
        global_manifest.save_global()?;

        println!("{} Removed {} (moved to gc)", "✓".green(), package);
    }

    // Update lock file
    let _ = crate::manifest::generate_lock(); // Ignore errors

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

    // Sync taps from global manifest first (packages may depend on taps)
    if !global_manifest.taps.is_empty() {
        println!("{}", "Syncing taps from global manifest:".magenta());

        for tap_name in global_manifest.taps.keys() {
            match homebrew::is_tap_tapped(tap_name) {
                Ok(true) => {
                    println!("  {} {} (already tapped)", "✓".green(), tap_name);
                }
                Ok(false) | Err(_) => {
                    println!("  {} {}", "→".blue(), tap_name);
                    homebrew::tap(tap_name)?;
                    synced_count += 1;
                }
            }
        }
        println!();
    }

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
        println!("{} Synced {} item(s)", "✓".green(), synced_count);
    } else {
        println!("{}", "All items already synced".yellow());
    }

    Ok(())
}

/// Check if environment is properly set up
pub fn check(quiet: bool) -> Result<()> {
    // Check if manifest exists
    if !Manifest::exists() {
        if !quiet {
            eprintln!("No manifest found. Run 'macdev init' first.");
        }
        std::process::exit(1);
    }

    let local_manifest = Manifest::load()?;
    let global_manifest = Manifest::load_global()?;

    // Check if all local packages are in global manifest (installed)
    let mut missing = Vec::new();
    for name in local_manifest.packages.keys() {
        if !global_manifest.packages.contains_key(name) {
            missing.push(name.clone());
        }
    }

    if !missing.is_empty() {
        if !quiet {
            eprintln!("Missing packages: {}", missing.join(", "));
            eprintln!("Run 'macdev install' to set up.");
        }
        std::process::exit(1);
    }

    // Check if profile directory exists
    let profile_bin = PathBuf::from(".macdev/profile/bin");
    if !profile_bin.exists() || fs::read_dir(&profile_bin)?.next().is_none() {
        if !quiet {
            eprintln!("Profile directory empty. Run 'macdev install'.");
        }
        std::process::exit(1);
    }

    if !quiet {
        println!("Environment is set up");
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

    // Update lock file
    let _ = crate::manifest::generate_lock(); // Ignore errors

    Ok(())
}

/// Upgrade packages
pub fn upgrade(package: Option<&str>) -> Result<()> {
    use colored::*;
    use std::process::Command;

    // Load manifests to know which packages are managed
    let local_manifest = Manifest::load().ok();
    let global_manifest = Manifest::load_global()?;

    if let Some(pkg) = package {
        // Upgrade specific package
        println!("{} {}", "Upgrading".cyan(), pkg);

        // Check if package is managed
        let pkg_base = pkg.split('@').next().unwrap();
        let is_pure = local_manifest.as_ref().is_some_and(|m| m.packages.contains_key(pkg_base));
        let is_impure = global_manifest.impure.contains_key(pkg_base);

        if !is_pure && !is_impure {
            anyhow::bail!("Package '{}' is not managed by macdev", pkg);
        }

        // Run brew upgrade
        let status = Command::new("brew")
            .args(["upgrade", pkg])
            .status()
            .context("Failed to run 'brew upgrade'")?;

        if !status.success() {
            anyhow::bail!("Failed to upgrade {}", pkg);
        }

        // Rebuild profile if pure package
        if is_pure {
            println!("  Rebuilding profile...");
            if let Some(local) = local_manifest {
                rebuild_profile(&local)?;
            }

            // Check if Python was upgraded
            if pkg_base == "python" || pkg.starts_with("python@") {
                println!();
                println!("  {} Python was upgraded. You may want to recreate the venv:", "ℹ".cyan());
                println!("    rm -rf .macdev/venv");
                println!("    macdev install");
            }
        }

        println!("{} Upgraded {}", "✓".green(), pkg);

        // Generate lock file
        let _ = crate::manifest::generate_lock(); // Ignore errors
    } else {
        // Upgrade all managed packages
        println!("{}", "Upgrading all managed packages...".cyan().bold());
        println!();

        let mut upgraded_count = 0;
        let mut python_upgraded = false;

        // Upgrade pure packages
        if let Some(local) = &local_manifest
            && !local.packages.is_empty() {
            println!("{}", "Upgrading pure packages:".green());
            for (name, version) in &local.packages {
                let spec = if version == "*" {
                    name.clone()
                } else {
                    format!("{}@{}", name, version)
                };

                println!("  {} {}", "→".blue(), spec);
                let output = Command::new("brew")
                    .args(["upgrade", &spec])
                    .output();

                if let Ok(output) = output {
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    // Check if actually upgraded (not "already installed")
                    if output.status.success() && !stderr.contains("already installed") {
                        upgraded_count += 1;
                        if name == "python" || spec.starts_with("python@") {
                            python_upgraded = true;
                        }
                    }
                }
            }
            println!();
        }

        // Upgrade impure packages
        if !global_manifest.impure.is_empty() {
            println!("{}", "Upgrading impure packages:".cyan());
            for name in global_manifest.impure.keys() {
                println!("  {} {}", "→".blue(), name);
                let output = Command::new("brew")
                    .args(["upgrade", name])
                    .output();

                if let Ok(output) = output {
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    // Check if actually upgraded (not "already installed")
                    if output.status.success() && !stderr.contains("already installed") {
                        upgraded_count += 1;
                    }
                }
            }
            println!();
        }

        // Rebuild profile if any pure packages were upgraded
        if let Some(local) = local_manifest
            && !local.packages.is_empty() {
            println!("Rebuilding profile...");
            rebuild_profile(&local)?;
        }

        if python_upgraded {
            println!();
            println!("  {} Python was upgraded. You may want to recreate the venv:", "ℹ".cyan());
            println!("    rm -rf .macdev/venv");
            println!("    macdev install");
        }

        println!();
        println!("{} Upgraded {} package(s)", "✓".green(), upgraded_count);
    }

    // Generate lock file
    let _ = crate::manifest::generate_lock(); // Ignore errors

    Ok(())
}

/// Install all packages from manifest
pub fn install() -> Result<()> {
    use colored::*;
    use crate::manifest::Lock;

    let local_manifest = Manifest::load()?;
    let mut global_manifest = Manifest::load_global()?;

    // Check if lock file exists - if so, use exact versions from lock
    let lock = if Lock::exists() {
        println!("{}", "Installing from lock file...".cyan().bold());
        Some(Lock::load()?)
    } else {
        println!("{}", "Installing packages from manifest...".cyan().bold());
        None
    };

    // Install pure packages from local manifest (no link)
    for (name, version) in &local_manifest.packages {
        let spec = if let Some(lock) = &lock {
            // Use exact version from lock file if available
            if let Some(locked_pkg) = lock.packages.get(name) {
                println!("  {} {} (locked: {})", "→".blue(), name, locked_pkg.version);
                locked_pkg.formula.clone()
            } else {
                // Fallback to manifest spec if not in lock
                if version == "*" {
                    name.clone()
                } else {
                    format!("{}@{}", name, version)
                }
            }
        } else {
            // No lock file, use manifest spec
            if version == "*" {
                name.clone()
            } else {
                format!("{}@{}", name, version)
            }
        };

        if lock.is_none() {
            println!("  {} {}", "→".blue(), spec);
        }

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

    // Generate lock file if it doesn't exist
    if lock.is_none() {
        let _ = crate::manifest::generate_lock(); // Ignore errors
    }

    Ok(())
}

/// Create symlinks for a package
fn create_symlinks(package: &str, brew_path: &Path) -> Result<()> {
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

    // Special handling for Python: create virtual environment
    if package.starts_with("python") {
        setup_python_venv(package)?;
    }

    Ok(())
}

/// Set up Python virtual environment for isolated package management
fn setup_python_venv(_package: &str) -> Result<()> {
    use colored::*;
    use std::process::Command;

    let venv_dir = PathBuf::from(".macdev/venv");

    // Skip if venv already exists
    if venv_dir.exists() {
        println!("  {} Python venv already exists", "✓".green());
        return Ok(());
    }

    println!("  {} Creating Python virtual environment...", "→".blue());

    // Get python3 from the profile
    let python_bin = PathBuf::from(".macdev/profile/bin/python3");
    if !python_bin.exists() {
        anyhow::bail!("Python binary not found in profile");
    }

    // Create venv
    let status = Command::new(&python_bin)
        .args(["-m", "venv", ".macdev/venv"])
        .status()
        .context("Failed to create virtual environment")?;

    if !status.success() {
        anyhow::bail!("Failed to create Python virtual environment");
    }

    println!("  {} Python venv created at .macdev/venv", "✓".green());
    println!();
    println!("  {} To activate, update your direnv config:", "ℹ".cyan());
    println!("    Add this to ~/.config/direnv/direnvrc:");
    println!();
    println!("    use_macdev() {{");
    println!("      if [[ ! -d .macdev ]]; then");
    println!("        log_error \"No .macdev directory found. Run 'macdev init' first.\"");
    println!("        return 1");
    println!("      fi");
    println!();
    println!("      if [[ ! -d .macdev/profile/bin ]] || [[ -z \"$(ls -A .macdev/profile/bin 2>/dev/null)\" ]]; then");
    println!("        log_status \"Setting up macdev environment...\"");
    println!("        macdev install");
    println!("      fi");
    println!();
    println!("      PATH_add .macdev/profile/bin");
    println!();
    println!("      # Activate Python venv if it exists");
    println!("      if [[ -f .macdev/venv/bin/activate ]]; then");
    println!("        source .macdev/venv/bin/activate");
    println!("      fi");
    println!();
    println!("      export MACDEV_ACTIVE=1");
    println!("    }}");
    println!();

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

/// Add a Homebrew tap
pub fn tap(tap_name: &str) -> Result<()> {
    use colored::*;

    // Check Homebrew is installed
    if !homebrew::is_installed() {
        anyhow::bail!("Homebrew is not installed. Install it from https://brew.sh");
    }

    let mut global_manifest = Manifest::load_global()?;

    // Check if already tapped and tracked
    if global_manifest.taps.contains_key(tap_name) {
        println!("{} Tap '{}' is already tracked", "⚠".yellow(), tap_name);
        return Ok(());
    }

    println!("{} {}", "Adding tap".green(), tap_name);

    // Add the tap if not already tapped
    if !homebrew::is_tap_tapped(tap_name)? {
        homebrew::tap(tap_name)?;
    } else {
        println!("  Tap already exists in Homebrew");
    }

    // Track in global manifest
    global_manifest.add_tap(tap_name.to_string());
    global_manifest.save_global()?;

    let path = Manifest::global_manifest_display_path()?;
    println!("{} Tap added (saved to {})", "✓".green(), path);

    Ok(())
}

/// Remove a Homebrew tap
pub fn untap(tap_name: &str) -> Result<()> {
    use colored::*;

    let mut global_manifest = Manifest::load_global()?;

    // Check if tap exists in manifest
    if !global_manifest.taps.contains_key(tap_name) {
        anyhow::bail!("Tap '{}' is not tracked", tap_name);
    }

    println!("{} {}", "Removing tap".yellow(), tap_name);

    // Remove from Homebrew
    if homebrew::is_tap_tapped(tap_name)? {
        homebrew::untap(tap_name)?;
    }

    // Remove from global manifest
    global_manifest.remove_tap(tap_name);
    global_manifest.save_global()?;

    println!("{} Tap removed", "✓".green());

    Ok(())
}
