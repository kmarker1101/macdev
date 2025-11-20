use anyhow::Result;
use macdev::cli::Cli;

fn main() -> Result<()> {
    let cli = Cli::parse();
    cli.run()
}
