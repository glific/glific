defmodule Glific.Assistants.AssistantTest do                                                                                        
     @moduledoc """                                                                                                                    
   -  Tests for Assistant schema and changesets                                                                                         
  3 +  Tests for Assistant, KnowledgeBase, KnowledgeBaseVersion, and AssistantConfigVersion schemas                                      
  4    """                                                                                                                               
  5    use Glific.DataCase                                                                                                               
  6                                                                                                                                      
  7 -  alias Glific.Assistants.Assistant                                                                                                 
  7 +  alias Glific.Assistants.{                                                                                                         
  8 +    Assistant,                                                                                                                      
  9 +    AssistantConfigVersion,                                                                                                         
 10 +    KnowledgeBase,                                                                                                                  
 11 +    KnowledgeBaseVersion                                                                                                            
 12 +  }                                                                                                                                 
 13                                                                                                                                      
  9 -  describe "changeset/2" do                                                                                                         
 14 +  describe "Assistant.changeset/2" do                                                                                               
 15      @valid_attrs %{                                                                                                                 
 16        name: "Test Assistant",                                                                                                       
 17        description: "A helpful assistant for testing"                                                                                
...                                                                                                                                      
 72      end                                                                                                                             
 73    end                                                                                                                               
 74                                                                                                                                      
 70 -  describe "set_active_config_version_changeset/2" do                                                                               
 75 +  describe "Assistant.set_active_config_version_changeset/2" do                                                                     
 76      test "valid changeset with active_config_version_id", %{organization_id: organization_id} do                                    
 77        assistant = %Assistant{                                                                                                       
 78          id: 1,                                                                                                                      
...                                                                                                                                      
 117        assert %{active_config_version_id: ["can't be blank"]} = errors_on(changeset)                                                
 118      end                                                                                                                            
 119    end                                                                                                                              
 120 +                                                                                                                                   
 121 +  describe "KnowledgeBase.changeset/2" do                                                                                          
 122 +    @valid_kb_attrs %{                                                                                                             
 123 +      name: "Test Knowledge Base"                                                                                                  
 124 +    }                                                                                                                              
 125 +                                                                                                                                   
 126 +    test "changeset with valid attributes", %{organization_id: organization_id} do                                                 
 127 +      attrs = Map.put(@valid_kb_attrs, :organization_id, organization_id)                                                          
 128 +      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, attrs)                                                                 
 129 +                                                                                                                                   
 130 +      assert changeset.valid?                                                                                                      
 131 +      assert get_change(changeset, :name) == "Test Knowledge Base"                                                                 
 132 +      assert get_change(changeset, :organization_id) == organization_id                                                            
 133 +    end                                                                                                                            
 134 +                                                                                                                                   
 135 +    test "changeset without name returns error", %{organization_id: organization_id} do                                            
 136 +      attrs = %{organization_id: organization_id}                                                                                  
 137 +      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, attrs)                                                                 
 138 +                                                                                                                                   
 139 +      refute changeset.valid?                                                                                                      
 140 +      assert %{name: ["can't be blank"]} = errors_on(changeset)                                                                    
 141 +    end                                                                                                                            
 142 +                                                                                                                                   
 143 +    test "changeset without organization_id returns error" do                                                                      
 144 +      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, @valid_kb_attrs)                                                       
 145 +                                                                                                                                   
 146 +      refute changeset.valid?                                                                                                      
 147 +      assert %{organization_id: ["can't be blank"]} = errors_on(changeset)                                                         
 148 +    end                                                                                                                            
 149 +                                                                                                                                   
 150 +    test "changeset with empty name returns error", %{organization_id: organization_id} do                                         
 151 +      attrs = %{                                                                                                                   
 152 +        name: "",                                                                                                                  
 153 +        organization_id: organization_id                                                                                           
 154 +      }                                                                                                                            
 155 +                                                                                                                                   
 156 +      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, attrs)                                                                 
 157 +                                                                                                                                   
 158 +      refute changeset.valid?                                                                                                      
 159 +    end                                                                                                                            
 160 +                                                                                                                                   
 161 +    test "changeset missing all required fields returns multiple errors" do                                                        
 162 +      changeset = KnowledgeBase.changeset(%KnowledgeBase{}, %{})                                                                   
 163 +                                                                                                                                   
 164 +      refute changeset.valid?                                                                                                      
 165 +      errors = errors_on(changeset)                                                                                                
 166 +      assert %{name: ["can't be blank"]} = errors                                                                                  
 167 +      assert %{organization_id: ["can't be blank"]} = errors                                                                       
 168 +    end                                                                                                                            
 169 +  end                                                                                                                              
 170 +                                                                                                                                   
 171 +  describe "KnowledgeBaseVersion.changeset/2" do                                                                                   
 172 +    @valid_kbv_attrs %{                                                                                                            
 173 +      files: %{"file1.pdf" => %{"size" => 1024, "pages" => 10}},                                                                   
 174 +      status: :completed,                                                                                                          
 175 +      llm_service_id: "vs_abc123"                                                                                                  
 176 +    }                                                                                                                              
 177 +                                                                                                                                   
 178 +    test "changeset with valid attributes", %{organization_id: organization_id} do                                                 
 179 +      attrs =                                                                                                                      
 180 +        @valid_kbv_attrs                                                                                                           
 181 +        |> Map.put(:organization_id, organization_id)                                                                              
 182 +        |> Map.put(:knowledge_base_id, 1)                                                                                          
 183 +                                                                                                                                   
 184 +      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)                                                   
 185 +                                                                                                                                   
 186 +      assert changeset.valid?                                                                                                      
 187 +      assert get_change(changeset, :files) == %{"file1.pdf" => %{"size" => 1024, "pages" => 10}}                                   
 188 +      assert get_change(changeset, :status) == :completed                                                                          
 189 +      assert get_change(changeset, :llm_service_id) == "vs_abc123"                                                                 
 190 +    end                                                                                                                            
 191 +                                                                                                                                   
 192 +    test "changeset without knowledge_base_id returns error", %{organization_id: organization_id} do                               
 193 +      attrs = Map.put(@valid_kbv_attrs, :organization_id, organization_id)                                                         
 194 +      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)                                                   
 195 +                                                                                                                                   
 196 +      refute changeset.valid?                                                                                                      
 197 +      assert %{knowledge_base_id: ["can't be blank"]} = errors_on(changeset)                                                       
 198 +    end                                                                                                                            
 199 +                                                                                                                                   
 200 +    test "changeset without files returns error", %{organization_id: organization_id} do                                           
 201 +      attrs = %{                                                                                                                   
 202 +        organization_id: organization_id,                                                                                          
 203 +        knowledge_base_id: 1,                                                                                                      
 204 +        status: :in_progress,                                                                                                      
 205 +        llm_service_id: "vs_abc123"                                                                                                
 206 +      }                                                                                                                            
 207 +                                                                                                                                   
 208 +      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)                                                   
 209 +                                                                                                                                   
 210 +      refute changeset.valid?                                                                                                      
 211 +      assert %{files: ["can't be blank"]} = errors_on(changeset)                                                                   
 212 +    end                                                                                                                            
 213 +                                                                                                                                   
 214 +    test "changeset without status returns error", %{organization_id: organization_id} do                                          
 215 +      attrs = %{                                                                                                                   
 216 +        organization_id: organization_id,                                                                                          
 217 +        knowledge_base_id: 1,                                                                                                      
 218 +        files: %{},                                                                                                                
 219 +        llm_service_id: "vs_abc123"                                                                                                
 220 +      }                                                                                                                            
 221 +                                                                                                                                   
 222 +      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)                                                   
 223 +                                                                                                                                   
 224 +      refute changeset.valid?                                                                                                      
 225 +      assert %{status: ["can't be blank"]} = errors_on(changeset)                                                                  
 226 +    end                                                                                                                            
 227 +                                                                                                                                   
 228 +    test "changeset without llm_service_id returns error", %{organization_id: organization_id} do                                  
 229 +      attrs = %{                                                                                                                   
 230 +        organization_id: organization_id,                                                                                          
 231 +        knowledge_base_id: 1,                                                                                                      
 232 +        files: %{},                                                                                                                
 233 +        status: :in_progress                                                                                                       
 234 +      }                                                                                                                            
 235 +                                                                                                                                   
 236 +      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)                                                   
 237 +                                                                                                                                   
 238 +      refute changeset.valid?                                                                                                      
 239 +      assert %{llm_service_id: ["can't be blank"]} = errors_on(changeset)                                                          
 240 +    end                                                                                                                            
 241 +                                                                                                                                   
 242 +    test "changeset with optional fields", %{organization_id: organization_id} do                                                  
 243 +      attrs =                                                                                                                      
 244 +        @valid_kbv_attrs                                                                                                           
 245 +        |> Map.put(:organization_id, organization_id)                                                                              
 246 +        |> Map.put(:knowledge_base_id, 1)                                                                                          
 247 +        |> Map.put(:size, 2048)                                                                                                    
 248 +        |> Map.put(:version_number, 1)                                                                                             
 249 +        |> Map.put(:kaapi_job_id, "job_xyz789")                                                                                    
 250 +                                                                                                                                   
 251 +      changeset = KnowledgeBaseVersion.changeset(%KnowledgeBaseVersion{}, attrs)                                                   
 252 +                                                                                                                                   
 253 +      assert changeset.valid?                                                                                                      
 254 +      assert get_change(changeset, :size) == 2048                                                                                  
 255 +      assert get_change(changeset, :version_number) == 1                                                                           
 256 +      assert get_change(changeset, :kaapi_job_id) == "job_xyz789"                                                                  
 257 +    end                                                                                                                            
 258 +                                                                                                                                   
 259 +    test "changeset with all status values", %{organization_id: organization_id} do                                                
 260 +      base_attrs = %{                                                                                                              
 261 +        organization_id: organization_id,                                                                                          
 262 +        knowledge_base_id: 1,                                                                                                      
 263 +        files: %{},                                                                                                                
 264 +        llm_service_id: "vs_abc123"                                                                                                
 265 +      }                                                                                                                            
 266 +                                                                                                                                   
 267 +      # Test in_progress status                                                                                                    
 268 +      changeset =                                                                                                                  
 269 +        KnowledgeBaseVersion.changeset(                                                                                            
 270 +          %KnowledgeBaseVersion{},                                                                                                 
 271 +          Map.put(base_attrs, :status, :in_progress)                                                                               
 272 +        )                                                                                                                          
 273 +                                                                                                                                   
 274 +      assert changeset.valid?                                                                                                      
 275 +      assert get_change(changeset, :status) == :in_progress                                                                        
 276 +                                                                                                                                   
 277 +      # Test completed status                                                                                                      
 278 +      changeset =                                                                                                                  
 279 +        KnowledgeBaseVersion.changeset(                                                                                            
 280 +          %KnowledgeBaseVersion{},                                                                                                 
 281 +          Map.put(base_attrs, :status, :completed)                                                                                 
 282 +        )                                                                                                                          
 283 +                                                                                                                                   
 284 +      assert changeset.valid?                                                                                                      
 285 +      assert get_change(changeset, :status) == :completed                                                                          
 286 +                                                                                                                                   
 287 +      # Test failed status                                                                                                         
 288 +      changeset =                                                                                                                  
 289 +        KnowledgeBaseVersion.changeset(                                                                                            
 290 +          %KnowledgeBaseVersion{},                                                                                                 
 291 +          Map.put(base_attrs, :status, :failed)                                                                                    
 292 +        )                                                                                                                          
 293 +                                                                                                                                   
 294 +      assert changeset.valid?                                                                                                      
 295 +      assert get_change(changeset, :status) == :failed                                                                             
 296 +    end                                                                                                                            
 297 +  end                                                                                                                              
 298 +                                                                                                                                   
 299 +  describe "AssistantConfigVersion.changeset/2" do                                                                                 
 300 +    @valid_acv_attrs %{                                                                                                            
 301 +      prompt: "You are a helpful assistant.",                                                                                      
 302 +      provider: "openai",                                                                                                          
 303 +      model: "gpt-4o",                                                                                                             
 304 +      kaapi_uuid: "kaapi-uuid-12345",                                                                                              
 305 +      settings: %{"temperature" => 0.7},                                                                                           
 306 +      status: :ready                                                                                                               
 307 +    }                                                                                                                              
 308 +                                                                                                                                   
 309 +    test "changeset with valid attributes", %{organization_id: organization_id} do                                                 
 310 +      attrs =                                                                                                                      
 311 +        @valid_acv_attrs                                                                                                           
 312 +        |> Map.put(:organization_id, organization_id)                                                                              
 313 +        |> Map.put(:assistant_id, 1)                                                                                               
 314 +                                                                                                                                   
 315 +      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)                                               
 316 +                                                                                                                                   
 317 +      assert changeset.valid?                                                                                                      
 318 +      assert get_change(changeset, :prompt) == "You are a helpful assistant."                                                      
 319 +      assert get_change(changeset, :provider) == "openai"                                                                          
 320 +      assert get_change(changeset, :model) == "gpt-4o"                                                                             
 321 +      assert get_change(changeset, :kaapi_uuid) == "kaapi-uuid-12345"                                                              
 322 +      assert get_change(changeset, :status) == :ready                                                                              
 323 +    end                                                                                                                            
 324 +                                                                                                                                   
 325 +    test "changeset without assistant_id returns error", %{organization_id: organization_id} do                                    
 326 +      attrs = Map.put(@valid_acv_attrs, :organization_id, organization_id)                                                         
 327 +      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)                                               
 328 +                                                                                                                                   
 329 +      refute changeset.valid?                                                                                                      
 330 +      assert %{assistant_id: ["can't be blank"]} = errors_on(changeset)                                                            
 331 +    end                                                                                                                            
 332 +                                                                                                                                   
 333 +    test "changeset without prompt returns error", %{organization_id: organization_id} do                                          
 334 +      attrs =                                                                                                                      
 335 +        @valid_acv_attrs                                                                                                           
 336 +        |> Map.delete(:prompt)                                                                                                     
 337 +        |> Map.put(:organization_id, organization_id)                                                                              
 338 +        |> Map.put(:assistant_id, 1)                                                                                               
 339 +                                                                                                                                   
 340 +      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)                                               
 341 +                                                                                                                                   
 342 +      refute changeset.valid?                                                                                                      
 343 +      assert %{prompt: ["can't be blank"]} = errors_on(changeset)                                                                  
 344 +    end                                                                                                                            
 345 +                                                                                                                                   
 346 +    test "changeset without provider returns error", %{organization_id: organization_id} do                                        
 347 +      attrs =                                                                                                                      
 348 +        @valid_acv_attrs                                                                                                           
 349 +        |> Map.delete(:provider)                                                                                                   
 350 +        |> Map.put(:organization_id, organization_id)                                                                              
 351 +        |> Map.put(:assistant_id, 1)                                                                                               
 352 +                                                                                                                                   
 353 +      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)                                               
 354 +                                                                                                                                   
 355 +      refute changeset.valid?                                                                                                      
 356 +      assert %{provider: ["can't be blank"]} = errors_on(changeset)                                                                
 357 +    end                                                                                                                            
 358 +                                                                                                                                   
 359 +    test "changeset without model returns error", %{organization_id: organization_id} do                                           
 360 +      attrs =                                                                                                                      
 361 +        @valid_acv_attrs                                                                                                           
 362 +        |> Map.delete(:model)                                                                                                      
 363 +        |> Map.put(:organization_id, organization_id)                                                                              
 364 +        |> Map.put(:assistant_id, 1)                                                                                               
 365 +                                                                                                                                   
 366 +      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)                                               
 367 +                                                                                                                                   
 368 +      refute changeset.valid?                                                                                                      
 369 +      assert %{model: ["can't be blank"]} = errors_on(changeset)                                                                   
 370 +    end                                                                                                                            
 371 +                                                                                                                                   
 372 +    test "changeset without kaapi_uuid returns error", %{organization_id: organization_id} do                                      
 373 +      attrs =                                                                                                                      
 374 +        @valid_acv_attrs                                                                                                           
 375 +        |> Map.delete(:kaapi_uuid)                                                                                                 
 376 +        |> Map.put(:organization_id, organization_id)                                                                              
 377 +        |> Map.put(:assistant_id, 1)                                                                                               
 378 +                                                                                                                                   
 379 +      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)                                               
 380 +                                                                                                                                   
 381 +      refute changeset.valid?                                                                                                      
 382 +      assert %{kaapi_uuid: ["can't be blank"]} = errors_on(changeset)                                                              
 383 +    end                                                                                                                            
 384 +                                                                                                                                   
 385 +    test "changeset without settings returns error", %{organization_id: organization_id} do                                        
 386 +      attrs =                                                                                                                      
 387 +        @valid_acv_attrs                                                                                                           
 388 +        |> Map.delete(:settings)                                                                                                   
 389 +        |> Map.put(:organization_id, organization_id)                                                                              
 390 +        |> Map.put(:assistant_id, 1)                                                                                               
 391 +                                                                                                                                   
 392 +      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)                                               
 393 +                                                                                                                                   
 394 +      refute changeset.valid?                                                                                                      
 395 +      assert %{settings: ["can't be blank"]} = errors_on(changeset)                                                                
 396 +    end                                                                                                                            
 397 +                                                                                                                                   
 398 +    test "changeset with optional fields", %{organization_id: organization_id} do                                                  
 399 +      attrs =                                                                                                                      
 400 +        @valid_acv_attrs                                                                                                           
 401 +        |> Map.put(:organization_id, organization_id)                                                                              
 402 +        |> Map.put(:assistant_id, 1)                                                                                               
 403 +        |> Map.put(:description, "Version 1 of the assistant")                                                                     
 404 +        |> Map.put(:version_number, 1)                                                                                             
 405 +        |> Map.put(:failure_reason, nil)                                                                                           
 406 +                                                                                                                                   
 407 +      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)                                               
 408 +                                                                                                                                   
 409 +      assert changeset.valid?                                                                                                      
 410 +      assert get_change(changeset, :description) == "Version 1 of the assistant"                                                   
 411 +      assert get_change(changeset, :version_number) == 1                                                                           
 412 +    end                                                                                                                            
 413 +                                                                                                                                   
 414 +    test "changeset with failure_reason when status is failed", %{organization_id: organization_id} do                             
 415 +      attrs =                                                                                                                      
 416 +        @valid_acv_attrs                                                                                                           
 417 +        |> Map.put(:organization_id, organization_id)                                                                              
 418 +        |> Map.put(:assistant_id, 1)                                                                                               
 419 +        |> Map.put(:status, :failed)                                                                                               
 420 +        |> Map.put(:failure_reason, "Failed to connect to LLM provider")                                                           
 421 +                                                                                                                                   
 422 +      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)                                               
 423 +                                                                                                                                   
 424 +      assert changeset.valid?                                                                                                      
 425 +      assert get_change(changeset, :status) == :failed                                                                             
 426 +      assert get_change(changeset, :failure_reason) == "Failed to connect to LLM provider"                                         
 427 +    end                                                                                                                            
 428 +                                                                                                                                   
 429 +    test "changeset with all status values", %{organization_id: organization_id} do                                                
 430 +      base_attrs =                                                                                                                 
 431 +        @valid_acv_attrs                                                                                                           
 432 +        |> Map.put(:organization_id, organization_id)                                                                              
 433 +        |> Map.put(:assistant_id, 1)                                                                                               
 434 +                                                                                                                                   
 435 +      # Test in_progress status                                                                                                    
 436 +      changeset =                                                                                                                  
 437 +        AssistantConfigVersion.changeset(                                                                                          
 438 +          %AssistantConfigVersion{},                                                                                               
 439 +          Map.put(base_attrs, :status, :in_progress)                                                                               
 440 +        )                                                                                                                          
 441 +                                                                                                                                   
 442 +      assert changeset.valid?                                                                                                      
 443 +      assert get_change(changeset, :status) == :in_progress                                                                        
 444 +                                                                                                                                   
 445 +      # Test ready status                                                                                                          
 446 +      changeset =                                                                                                                  
 447 +        AssistantConfigVersion.changeset(                                                                                          
 448 +          %AssistantConfigVersion{},                                                                                               
 449 +          Map.put(base_attrs, :status, :ready)                                                                                     
 450 +        )                                                                                                                          
 451 +                                                                                                                                   
 452 +      assert changeset.valid?                                                                                                      
 453 +      assert get_change(changeset, :status) == :ready                                                                              
 454 +                                                                                                                                   
 455 +      # Test failed status                                                                                                         
 456 +      changeset =                                                                                                                  
 457 +        AssistantConfigVersion.changeset(                                                                                          
 458 +          %AssistantConfigVersion{},                                                                                               
 459 +          Map.put(base_attrs, :status, :failed)                                                                                    
 460 +        )                                                                                                                          
 461 +                                                                                                                                   
 462 +      assert changeset.valid?                                                                                                      
 463 +      assert get_change(changeset, :status) == :failed                                                                             
 464 +    end                                                                                                                            
 465 +                                                                                                                                   
 466 +    test "changeset with deleted_at for soft delete", %{organization_id: organization_id} do                                       
 467 +      deleted_at = DateTime.utc_now()                                                                                              
 468 +                                                                                                                                   
 469 +      attrs =                                                                                                                      
 470 +        @valid_acv_attrs                                                                                                           
 471 +        |> Map.put(:organization_id, organization_id)                                                                              
 472 +        |> Map.put(:assistant_id, 1)                                                                                               
 473 +        |> Map.put(:deleted_at, deleted_at)                                                                                        
 474 +                                                                                                                                   
 475 +      changeset = AssistantConfigVersion.changeset(%AssistantConfigVersion{}, attrs)                                               
 476 +                                                                                                                                   
 477 +      assert changeset.valid?                                                                                                      
 478 +      assert get_change(changeset, :deleted_at) == deleted_at                                                                      
 479 +    end                                                                                                                            
 480 +  end                                                                                                                              
 481  end    