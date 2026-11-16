use std::sync::Mutex;

static ANSWER: Mutex<u32> = Mutex::new(41);

#[unsafe(no_mangle)]
pub extern "C" fn answer() -> u32 {
    let mut answer = ANSWER.lock().unwrap();

    *answer += 1;
    *answer
}
