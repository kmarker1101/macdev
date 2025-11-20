use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "macdev")]
#[command(about = "Project-isolated development environments using Homebrew")]
pub struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialize a new macdev environment
    Init,
    
    /// Add packages to the environment
    Add {
        /// Package specifications (e.g., python@3.11 rust node)
        packages: Vec<String>,

        /// Make packages available system-wide (impure)
        #[arg(long)]
        impure: bool,
    },

    /// Remove packages from the environment
    Remove {
        /// Package names
        packages: Vec<String>,
    },
    
    /// Install all packages from manifest
    Install,
    
    /// Enter the isolated shell environment
    Shell,

    /// List packages in the environment
    List,

    /// Sync packages from manifest(s)
    Sync,

    /// Garbage collect unused packages
    Gc,

    /// Add a Homebrew tap
    Tap {
        /// Tap name (e.g., homebrew/cask)
        tap: String,
    },

    /// Remove a Homebrew tap
    Untap {
        /// Tap name (e.g., homebrew/cask)
        tap: String,
    },
}

impl Cli {
    pub fn parse() -> Self {
        <Self as Parser>::parse()
    }
    
    pub fn run(self) -> Result<()> {
        match self.command {
            Commands::Init => crate::manifest::init(),
            Commands::Add { packages, impure } => {
                for package in &packages {
                    crate::environment::add(package, impure)?;
                }
                Ok(())
            }
            Commands::Remove { packages } => {
                for package in &packages {
                    crate::environment::remove(package)?;
                }
                Ok(())
            }
            Commands::Install => crate::environment::install(),
            Commands::Shell => crate::shell::enter(),
            Commands::List => crate::manifest::list(),
            Commands::Sync => crate::environment::sync(),
            Commands::Gc => crate::environment::gc(),
            Commands::Tap { tap } => crate::environment::tap(&tap),
            Commands::Untap { tap } => crate::environment::untap(&tap),
        }
    }
}
