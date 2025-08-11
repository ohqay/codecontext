use libc::{c_char, c_int, size_t};
use std::ffi::{CStr, CString};
use std::ptr;
use tiktoken_rs::{cl100k_base, CoreBPE};

static mut TOKENIZER: Option<CoreBPE> = None;
static INIT: std::sync::Once = std::sync::Once::new();

/// Initialize the tokenizer with cl100k_base encoding
/// Returns 0 on success, -1 on failure
#[no_mangle]
pub extern "C" fn tokenizer_initialize() -> c_int {
    INIT.call_once(|| {
        // Initialize with cl100k_base encoding (GPT-4/GPT-3.5-turbo)
        // This will use the bundled vocabulary data
        match cl100k_base() {
            Ok(bpe) => unsafe {
                TOKENIZER = Some(bpe);
            },
            Err(e) => {
                eprintln!("Failed to initialize tokenizer: {}", e);
            }
        }
    });
    
    unsafe {
        if TOKENIZER.is_some() {
            0
        } else {
            -1
        }
    }
}

/// Count tokens in the given text
/// Returns the token count, or -1 on error
#[no_mangle]
pub extern "C" fn tokenizer_count_tokens(text: *const c_char) -> c_int {
    if text.is_null() {
        return 0;
    }
    
    let c_str = unsafe { CStr::from_ptr(text) };
    let text_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };
    
    if text_str.is_empty() {
        return 0;
    }
    
    unsafe {
        match &TOKENIZER {
            Some(bpe) => {
                let tokens = bpe.encode_ordinary(text_str);
                tokens.len() as c_int
            }
            None => -1,
        }
    }
}

/// Encode text to tokens
/// Returns the number of tokens, fills the tokens array
/// tokens_buffer must be pre-allocated with sufficient size
#[no_mangle]
pub extern "C" fn tokenizer_encode(
    text: *const c_char,
    tokens_buffer: *mut c_int,
    buffer_size: size_t,
) -> c_int {
    if text.is_null() || tokens_buffer.is_null() {
        return -1;
    }
    
    let c_str = unsafe { CStr::from_ptr(text) };
    let text_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };
    
    unsafe {
        match &TOKENIZER {
            Some(bpe) => {
                let tokens = bpe.encode_ordinary(text_str);
                let count = tokens.len().min(buffer_size);
                
                #[cfg(debug_assertions)]
                eprintln!("[tokenizer_encode] Input: {:?}, Generated {} tokens: {:?}", 
                          text_str, tokens.len(), tokens);
                
                for (i, token) in tokens.iter().take(count).enumerate() {
                    *tokens_buffer.add(i) = *token as c_int;
                }
                
                tokens.len() as c_int
            }
            None => -1,
        }
    }
}

/// Decode tokens back to text
/// Returns a null-terminated C string that must be freed by the caller
#[no_mangle]
pub extern "C" fn tokenizer_decode(tokens: *const c_int, token_count: size_t) -> *mut c_char {
    if tokens.is_null() || token_count == 0 {
        return ptr::null_mut();
    }
    
    unsafe {
        match &TOKENIZER {
            Some(bpe) => {
                let tokens_slice = std::slice::from_raw_parts(tokens, token_count);
                let tokens_vec: Vec<u32> = tokens_slice.iter().map(|&t| t as u32).collect();
                
                #[cfg(debug_assertions)]
                eprintln!("[tokenizer_decode] Decoding {} tokens: {:?}", token_count, tokens_vec);
                
                match bpe.decode(tokens_vec) {
                    Ok(text) => {
                        #[cfg(debug_assertions)]
                        eprintln!("[tokenizer_decode] Decoded text: {:?} (len: {})", text, text.len());
                        
                        match CString::new(text) {
                            Ok(c_string) => c_string.into_raw(),
                            Err(e) => {
                                #[cfg(debug_assertions)]
                                eprintln!("[tokenizer_decode] CString error: {:?}", e);
                                ptr::null_mut()
                            }
                        }
                    }
                    Err(e) => {
                        #[cfg(debug_assertions)]
                        eprintln!("[tokenizer_decode] Decode error: {:?}", e);
                        ptr::null_mut()
                    }
                }
            }
            None => ptr::null_mut(),
        }
    }
}

/// Free a string returned by tokenizer_decode
#[no_mangle]
pub extern "C" fn tokenizer_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// Check if the tokenizer is initialized
#[no_mangle]
pub extern "C" fn tokenizer_is_ready() -> c_int {
    unsafe {
        if TOKENIZER.is_some() {
            1
        } else {
            0
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;
    
    #[test]
    fn test_initialization() {
        assert_eq!(tokenizer_initialize(), 0);
        assert_eq!(tokenizer_is_ready(), 1);
    }
    
    #[test]
    fn test_count_tokens() {
        tokenizer_initialize();
        
        let text = CString::new("Hello, world!").unwrap();
        let count = tokenizer_count_tokens(text.as_ptr());
        assert_eq!(count, 3); // "Hello", ", world", "!"
    }
    
    #[test]
    fn test_empty_string() {
        tokenizer_initialize();
        
        let text = CString::new("").unwrap();
        let count = tokenizer_count_tokens(text.as_ptr());
        assert_eq!(count, 0);
    }
}
