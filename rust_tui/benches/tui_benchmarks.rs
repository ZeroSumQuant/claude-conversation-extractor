use criterion::{black_box, criterion_group, criterion_main, Criterion};
use claude_tui::backend::{SearchEngine, ConversationParser};
use claude_tui::state::{AppState, Action};

fn benchmark_search(c: &mut Criterion) {
    let runtime = tokio::runtime::Runtime::new().unwrap();
    
    c.bench_function("search_fuzzy", |b| {
        let search_engine = SearchEngine::new();
        b.iter(|| {
            runtime.block_on(async {
                let result = search_engine.search(black_box("test query")).await;
                black_box(result)
            })
        })
    });
}

fn benchmark_state_reduction(c: &mut Criterion) {
    c.bench_function("state_reduce", |b| {
        let mut state = AppState::new();
        b.iter(|| {
            let effects = state.reduce(black_box(Action::Tick));
            black_box(effects)
        })
    });
}

fn benchmark_parser(c: &mut Criterion) {
    c.bench_function("parse_conversation", |b| {
        let parser = ConversationParser::new();
        let sample_content = r#"
        User: Hello, how are you?
        Assistant: I'm doing well, thank you for asking!
        User: Can you help me with something?
        Assistant: Of course! I'd be happy to help.
        "#;
        
        b.iter(|| {
            let result = parser.parse_content(black_box(sample_content));
            black_box(result)
        })
    });
}

criterion_group!(benches, benchmark_search, benchmark_state_reduction, benchmark_parser);
criterion_main!(benches);