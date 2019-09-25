class: Workflow
cwlVersion: v1.0
id: make_bam_and_qc
label: make_bam_and_qc
inputs:
  reference_sequence:
    type: File
    secondaryFiles:
      - .amb
      - .ann
      - .bwt
      - .pac
      - .sa
      - .fai
      - ^.dict

  tumor_sample:
    type:
      type: record
      fields:
        ID: string
        CN: string
        LB: string
        PL: string
        PU: string[]
        R1: File[]
        R2: File[]
        RG_ID: string[]
        adapter: string
        adapter2: string
        bwa_output: string

  normal_sample:
    type: 
      type: record
      fields:
        ID: string
        CN: string
        LB: string
        PL: string
        PU: string[]
        R1: File[]
        R2: File[]
        RG_ID: string[]
        adapter: string
        adapter2: string
        bwa_output: string

  known_sites:
    type:
      type: array
      items: File
    secondaryFiles:
      - .idx

  target_bed:
    type: File?
    secondaryFiles:
      - .tbi

  targets_list:
    type: File?

  baits_list:
    type: File?

outputs:
  tumor_bam:
    type: File
    outputSource: make_bams/tumor_bam
    secondaryFiles:
      - ^.bai
  normal_bam:
    type: File
    outputSource: make_bams/normal_bam
    secondaryFiles:
      - ^.bai

  dir_qc:
    type: Directory
    outputSource: put_in_dir_qc/directory

  dir_bams:
    type: Directory
    outputSource: put_in_dir_bams/directory

steps:
  # combines R1s and R2s from both tumor and normal samples
  run_qc_fastqs:
    in:
      tumor_sample: tumor_sample
      normal_sample: normal_sample
      r1:
        valueFrom: ${ var data = []; data = inputs.tumor_sample.R1.concat(inputs.normal_sample.R1); return data }
      r2:
        valueFrom: ${ var data = []; data = inputs.tumor_sample.R2.concat(inputs.normal_sample.R2); return data }
      output_prefix:
        valueFrom: ${ var data = []; data = inputs.tumor_sample.RG_ID.concat(inputs.normal_sample.RG_ID); return data }
    out: [ fastp_html, fastp_json ]
    run: tempo_qc/qc_fastqs/scatter_fastqs_for_qc.cwl

  run_collect_hsmetrics:
    in:
      REFERENCE_SEQUENCE: reference_sequence
      INPUT:
        source: [ make_bams/tumor_bam, make_bams/normal_bam ]
        linkMerge: merge_flattened
      TARGET_INTERVALS: targets_list
      BAIT_INTERVALS: baits_list
      OUTPUT:
        valueFrom: ${ return inputs.INPUT.basename.replace(".bam", "_hsmetrics.txt"); }
    out: [ out_file ]
    scatter: [ INPUT ]
    scatterMethod: dotproduct
    run: tempo_qc/qc_wrapper/collect_hs_metrics.cwl

  make_bams:
    in:
      tumor_sample: tumor_sample
      normal_sample: normal_sample
      reference_sequence: reference_sequence
      known_sites: known_sites
    out: [ tumor_bam, normal_bam ]
    run: preprocess_tumor_normal_bam/preprocess_tumor_normal_pair.cwl

  run_alfred:
    in:
      bam:
        source: [ make_bams/tumor_bam, make_bams/normal_bam ]
        linkMerge: merge_flattened
      bed: target_bed
      reference_sequence: reference_sequence
    out: [ bam_qc_alfred_rg, bam_qc_alfred_ignore_rg, bam_qc_alfred_rg_pdf, bam_qc_alfred_ignore_rg_pdf ]
    run: tempo_qc/qc_bams/run_alfred.cwl
    scatter: [ bam ]
    scatterMethod: dotproduct

  make_dir_fastq_qc:
    in:
      tumor_sample: tumor_sample
      normal_sample: normal_sample
      files:
        source: [ run_qc_fastqs/fastp_html, run_qc_fastqs/fastp_json, run_collect_hsmetrics/out_file ]
        linkMerge: merge_flattened
      output_directory_name:
        valueFrom: ${ return "fastqs"; }
    out: [ directory ]
    run: utils/put_files_in_dir.cwl

  make_dir_bam_qc:
    in:
      tumor_sample: tumor_sample
      normal_sample: normal_sample
      files: 
        source: [ run_alfred/bam_qc_alfred_rg, run_alfred/bam_qc_alfred_ignore_rg, run_alfred/bam_qc_alfred_rg_pdf, run_alfred/bam_qc_alfred_ignore_rg_pdf ]
        linkMerge: merge_flattened
      output_directory_name:
        valueFrom: ${ return "bams"; }
    out: [ directory ]
    run: utils/put_files_in_dir.cwl

  put_in_dir_qc:
    in:
      files:
        source: [ make_dir_fastq_qc/directory, make_dir_bam_qc/directory ]
      output_directory_name:
        valueFrom: ${ return "qc"; }
    out: [ directory ]
    run: utils/put_files_in_dir.cwl

  put_in_dir_bams:
    in:
      files:
        source: [ make_bams/tumor_bam, make_bams/normal_bam ]
        linkMerge: merge_flattened
      output_directory_name: 
        valueFrom: ${ return "bams"; }
    out: [ directory ]
    run: utils/put_files_in_dir.cwl 
  
requirements:
  - class: SubworkflowFeatureRequirement
  - class: ScatterFeatureRequirement
  - class: InlineJavascriptRequirement
  - class: StepInputExpressionRequirement
