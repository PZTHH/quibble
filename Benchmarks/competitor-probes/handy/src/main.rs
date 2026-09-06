mod handy;
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct Fixture {
    text: String,
    words: Vec<String>,
    expected: String,
}

#[derive(Serialize)]
struct ResultRow {
    text: String,
    words: Vec<String>,
    expected: String,
    output: String,
    matched: bool,
    negative: bool,
    false_correction: bool,
    elapsed_microseconds: f64,
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    assert_eq!(args.len(), 3, "usage: probe fixtures.json results.json");
    let fixtures: Vec<Fixture> = serde_json::from_str(
        &std::fs::read_to_string(&args[1]).expect("read fixtures"),
    ).expect("parse fixtures");
    let rows: Vec<ResultRow> = fixtures.into_iter().map(|f| {
        let start = std::time::Instant::now();
        let output = handy::apply_custom_words(&f.text, &f.words, 0.18);
        let elapsed_microseconds = start.elapsed().as_secs_f64() * 1_000_000.0;
        ResultRow {
            matched: output == f.expected,
            negative: f.expected == f.text,
            false_correction: f.expected == f.text && output != f.text,
            text: f.text, words: f.words, expected: f.expected, output, elapsed_microseconds,
        }
    }).collect();
    std::fs::write(&args[2], serde_json::to_string_pretty(&rows).unwrap()).unwrap();
    println!("{} / {} exact matches; {} / {} negatives falsely changed", rows.iter().filter(|r| r.matched).count(), rows.len(), rows.iter().filter(|r| r.false_correction).count(), rows.iter().filter(|r| r.negative).count());
}
