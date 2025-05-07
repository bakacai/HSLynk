use hidapi;
use lazy_static::lazy_static;
use std::string::ToString;
use std::sync::Mutex;
use thiserror::Error;

lazy_static! {
    static ref HID_API: Mutex<hidapi::HidApi> =
        Mutex::new(hidapi::HidApi::new().expect("Failed to create HidApi instance"));
    static ref HSLink_VID: u16 = 0x0D28;
    static ref HSLink_PID: u16 = 0x0204;
    static ref HSLink_DEVICE: Mutex<Option<hidapi::HidDevice>> = Mutex::new(None);
    static ref HSLink_DONW_REPORT_ID: u8 = 0x01;
    static ref HSLink_UP_REPORT_ID: u8 = 0x02;
}

// add HSLinkError to let frontend to handle it
#[derive(Error, Debug)]
pub enum HSLinkError {
    #[error("HSLinkError: Device not found")]
    DeviceNotFound,
    #[error("HSLinkError: Device not opened")]
    DeviceNotOpened,
    #[error("HSLinkError: Write error")]
    WriteErr,
    #[error("HSLinkError: Read error")]
    ReadErr,
    #[error("HSLinkError: Response error")]
    RspErr,
    #[error("HSLinkError: NotSupport")]
    NotSupport,
}

impl serde::Serialize for HSLinkError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::ser::Serializer,
    {
        serializer.serialize_str(self.to_string().as_ref())
    }
}

// hslink_list_device函数用于列出所有已连接的HSLink设备
// 返回一个包含所有HSLink设备序列号的字符串向量
pub fn hslink_list_device() -> Vec<String> {
    // 创建一个空的字符串向量用于存储设备序列号
    let mut devices: Vec<String> = Vec::new();
    
    // 获取HID API的互斥锁并刷新设备列表
    let mut hid_api = HID_API.lock().unwrap();
    hid_api.refresh_devices().unwrap();
    
    // 遍历所有HID设备
    for device_info in hid_api.device_list() {
        // 检查设备的VID和PID是否匹配HSLink设备
        if device_info.vendor_id() == *HSLink_VID && device_info.product_id() == *HSLink_PID {
            // 打印找到的设备信息
            println!("Device Found:");
            println!("  Vendor ID: {:04X}", device_info.vendor_id());
            println!("  Product ID: {:04X}", device_info.product_id());
            println!("  Path: {:?}", device_info.path());
            println!("  Serial Number: {:?}", device_info.serial_number());
            
            // 如果设备有序列号,则添加到设备列表中
            if !device_info.serial_number().is_none() {
                devices.push(device_info.serial_number().unwrap().to_string());
            }
        }
    }
    
    // 如果没有找到设备则打印提示信息
    if devices.is_empty() {
        println!("No HSLink devices found");
    }
    
    // 返回找到的设备序列号列表
    devices
}

// hslink_open_device函数用于打开指定序列号的HSLink设备
// 参数:
// - serial_number: 要打开的设备序列号
// 返回:
// - Ok(String): 成功打开设备后返回设备序列号
// - Err(HSLinkError): 打开失败的错误类型
pub fn hslink_open_device(serial_number: String) -> Result<String, HSLinkError> {
    // 获取设备和HID API的互斥锁
    let mut device_lock = HSLink_DEVICE.lock().unwrap();
    let mut hid_api = HID_API.lock().unwrap();

    // 遍历所有HID设备
    for device_info in hid_api.device_list() {
        // 检查设备的VID和PID是否匹配HSLink设备
        if device_info.vendor_id() == *HSLink_VID && device_info.product_id() == *HSLink_PID {
            // 检查序列号是否匹配目标设备
            if device_info.serial_number().unwrap().to_string() == serial_number {
                // 尝试打开设备
                match hid_api.open_path(device_info.path()) {
                    Ok(device) => {
                        println!("Device Opened: {:?}", device);
                        let sn = device_info.serial_number().unwrap().to_string();
                        // 再次验证序列号匹配
                        if sn != serial_number {
                            return Err(HSLinkError::DeviceNotFound);
                        }
                        // 保存设备句柄
                        *device_lock = Some(device);
                        return Ok(sn);
                    }
                    Err(err) => {
                        println!("Error opening device: {:?}", err);
                        return Err(HSLinkError::DeviceNotOpened);
                    }
                }
            }
        }
    }
    // 未找到匹配的设备
    Err(HSLinkError::DeviceNotFound)
}

// hslink_write函数用于向HSLink设备写入数据
// 参数:
// - data: 要发送的数据字节数组
// 返回:
// - Ok(()): 写入成功
// - Err(HSLinkError): 写入失败的错误类型
pub fn hslink_write(data: Vec<u8>) -> Result<(), HSLinkError> {
    // 获取设备的互斥锁
    let mut device_lock = HSLink_DEVICE.lock().unwrap();
    
    // 创建发送缓冲区,长度为数据长度+1(用于存放报告ID)
    let mut buff = vec![0u8; data.len() + 1];
    // 设置HID报告ID
    buff[0] = *HSLink_DONW_REPORT_ID;
    // 将数据复制到缓冲区中(从索引1开始)
    (&mut buff[1..]).copy_from_slice(&data);
    buff.resize(1024, 0);

    // 检查设备是否已打开
    if let Some(ref mut device) = *device_lock {
        // 向设备写入数据
        match device.write(&buff) {
            Ok(res) => {
                println!("Wrote: {:?} byte(s)", res);
                Ok(()) // 写入成功
            }
            Err(err) => {
                println!("Error writing to device: {:?}", err);
                Err(HSLinkError::WriteErr) // 写入错误
            }
        }
    } else {
        println!("Device not opened");
        Err(HSLinkError::DeviceNotOpened) // 设备未打开错误
    }
}

// hslink_write_wait_rsp函数用于向HSLink设备写入数据并等待响应
// 参数:
// - data: 要发送的数据字节数组
// - timeout: 等待响应的超时时间(毫秒)
// 返回:
// - Ok(String): 成功接收到的响应字符串
// - Err(HSLinkError): 操作失败的错误类型
pub fn hslink_write_wait_rsp(data: Vec<u8>, timeout: u32) -> Result<String, HSLinkError> {
    // 首先调用hslink_write发送数据
    let write_err = hslink_write(data);
    // 如果写入失败,直接返回错误
    if write_err.is_err() {
        return Err(write_err.unwrap_err());
    }
    
    // 获取设备的互斥锁
    let mut device_lock = HSLink_DEVICE.lock().unwrap();
    // 创建1024字节的接收缓冲区
    let mut recv_buf = [0u8; 1024];
    
    // 检查设备是否已打开
    if let Some(ref mut device) = *device_lock {
        // 使用超时读取设备响应
        match device.read_timeout(&mut recv_buf, timeout as i32) {
            Ok(res) => {
                println!("Read: {:?}", res);
                // 检查响应的报告ID是否正确
                if recv_buf[0] == *HSLink_UP_REPORT_ID {
                    // 查找第一个\0字符,用于确定有效数据的长度
                    let mut i = 0;
                    while i < res && recv_buf[i] != 0 {
                        i += 1;
                    }
                    // 提取有效数据(不包含报告ID)
                    let data = recv_buf[1..i].to_vec();
                    println!("Received: {:?}", data);
                    // 将数据转换为UTF-8字符串并返回
                    Ok(String::from_utf8(data).unwrap().to_string())
                } else {
                    // 报告ID不正确
                    Err(HSLinkError::RspErr)
                }
            }
            Err(err) => {
                // 读取错误
                println!("Error reading from device: {:?}", err);
                Err(HSLinkError::ReadErr)
            }
        }
    } else {
        // 设备未打开
        Err(HSLinkError::DeviceNotOpened)
    }
}

pub fn hslink_close_device() -> Result<(), HSLinkError> {
    let mut device_lock = HSLink_DEVICE.lock().unwrap();
    if let Some(_) = *device_lock {
        *device_lock = None;
        println!("设备已关闭");
        Ok(())
    } else {
        println!("设备未打开");
        Err(HSLinkError::DeviceNotOpened)
    }
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}
